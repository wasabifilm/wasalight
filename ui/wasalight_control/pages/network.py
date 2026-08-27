# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Touch-first NetworkManager configuration page."""

import ipaddress
import json
import os
import socket
import uuid

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("NM", "1.0")
from gi.repository import GLib, Gtk, NM

from ..i18n import _
from ..widgets import prepare_dialog, section_heading
from .common import scroll_page


class NetworkPage:
    def __init__(self, parent, run_command, show_error, paths, runner,
                 background_command):
        self.parent = parent
        self.run_command = run_command
        self.show_error = show_error
        self.paths = paths
        self.runner = runner
        self.background_command = background_command
        self.client = None
        self.devices = []
        self.magicq_configuration = None

        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("Network"),
            _("Configure Ethernet, Wi-Fi and persistent IP settings.")),
            False, False, 0)

        interface_card = Gtk.Frame()
        interface_card.get_style_context().add_class("flat-card")
        interface_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        interface_box.set_border_width(16)
        selector_row = Gtk.Box(spacing=12)
        selector_row.pack_start(Gtk.Label(label=_("Interface")), False, False, 0)
        self.device_selector = Gtk.ComboBoxText()
        self.device_selector.set_hexpand(True)
        self.device_selector.connect("changed", self.device_changed)
        selector_row.pack_start(self.device_selector, True, True, 0)
        refresh = Gtk.Button(label=_("Refresh"))
        refresh.connect("clicked", lambda _button: self.refresh())
        selector_row.pack_start(refresh, False, False, 0)
        interface_box.pack_start(selector_row, False, False, 0)
        self.device_status = Gtk.Label()
        self.device_status.set_xalign(0)
        self.device_status.set_line_wrap(True)
        self.device_status.get_style_context().add_class("section-subtitle")
        interface_box.pack_start(self.device_status, False, False, 0)
        interface_card.add(interface_box)
        page.pack_start(interface_card, False, False, 0)

        magicq_card = Gtk.Frame()
        magicq_card.get_style_context().add_class("flat-card")
        magicq_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        magicq_box.set_border_width(16)
        magicq_box.pack_start(section_heading(
            _("MagicQ lighting network"),
            _("Add the address saved by MagicQ without replacing the main Linux address.")),
            False, False, 0)
        self.magicq_status = Gtk.Label()
        self.magicq_status.set_xalign(0)
        self.magicq_status.set_line_wrap(True)
        self.magicq_status.get_style_context().add_class("section-subtitle")
        magicq_box.pack_start(self.magicq_status, False, False, 0)
        self.magicq_sync_button = Gtk.Button(label=_("Synchronize with MagicQ"))
        self.magicq_sync_button.get_style_context().add_class("primary-button")
        self.magicq_sync_button.connect("clicked", self.sync_magicq)
        magicq_box.pack_start(self.magicq_sync_button, False, False, 0)
        magicq_card.add(magicq_box)
        page.pack_start(magicq_card, False, False, 0)

        ipv4_card = Gtk.Frame()
        ipv4_card.get_style_context().add_class("flat-card")
        ipv4_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        ipv4_box.set_border_width(16)
        ipv4_box.pack_start(section_heading(
            _("IPv4 configuration"),
            _("Use DHCP or assign a persistent address to the selected interface.")),
            False, False, 0)
        method_row = Gtk.Box(spacing=12)
        self.dhcp = Gtk.RadioButton.new_with_label_from_widget(None, _("Automatic (DHCP)"))
        self.manual = Gtk.RadioButton.new_with_label_from_widget(
            self.dhcp, _("Manual address"))
        self.dhcp.connect("toggled", self.method_changed)
        method_row.pack_start(self.dhcp, False, False, 0)
        method_row.pack_start(self.manual, False, False, 0)
        ipv4_box.pack_start(method_row, False, False, 0)

        grid = Gtk.Grid(column_spacing=12, row_spacing=9)
        self.address = self._field(grid, 0, _("IP address"), "192.168.1.100")
        self.prefix = self._field(grid, 1, _("Prefix"), "24")
        self.gateway = self._field(grid, 2, _("Gateway"), "192.168.1.1")
        self.dns = self._field(grid, 3, _("DNS servers"), "1.1.1.1, 8.8.8.8")
        ipv4_box.pack_start(grid, False, False, 0)
        actions = Gtk.Box(spacing=10)
        self.save_button = Gtk.Button(label=_("Save and apply"))
        self.save_button.get_style_context().add_class("primary-button")
        self.save_button.connect("clicked", self.save_ipv4)
        actions.pack_start(self.save_button, False, False, 0)
        self.disconnect_button = Gtk.Button(label=_("Disconnect"))
        self.disconnect_button.connect("clicked", self.disconnect)
        actions.pack_start(self.disconnect_button, False, False, 0)
        ipv4_box.pack_start(actions, False, False, 0)
        ipv4_card.add(ipv4_box)
        page.pack_start(ipv4_card, False, False, 0)

        wifi_heading = Gtk.Box(spacing=10)
        wifi_heading.pack_start(section_heading(
            _("Wi-Fi networks"),
            _("Select a network. Saved credentials are reused automatically.")),
            True, True, 0)
        scan = Gtk.Button(label=_("Scan"))
        scan.connect("clicked", self.scan_wifi)
        wifi_heading.pack_start(scan, False, False, 0)
        advanced = Gtk.Button(label=_("Advanced"))
        advanced.connect(
            "clicked", lambda button: run_command(button, ["lxterminal", "-e", "nmtui"]))
        wifi_heading.pack_start(advanced, False, False, 0)
        page.pack_start(wifi_heading, False, False, 0)
        self.wifi_list = Gtk.ListBox()
        self.wifi_list.set_selection_mode(Gtk.SelectionMode.NONE)
        page.pack_start(self.wifi_list, False, False, 0)

        self.widget = scroll_page(page)
        self.refresh()

    @staticmethod
    def _field(grid, row, label, placeholder):
        text = Gtk.Label(label=label)
        text.set_xalign(0)
        grid.attach(text, 0, row, 1, 1)
        entry = Gtk.Entry()
        entry.set_hexpand(True)
        entry.set_placeholder_text(placeholder)
        grid.attach(entry, 1, row, 1, 1)
        return entry

    def _ensure_client(self):
        if self.client is None:
            self.client = NM.Client.new(None)
        return self.client

    def refresh(self):
        selected = self.current_device().get_iface() if self.current_device() else None
        try:
            client = self._ensure_client()
            self.devices = [
                device for device in client.get_devices()
                if device.get_device_type() in (NM.DeviceType.ETHERNET, NM.DeviceType.WIFI)
            ]
        except Exception as error:
            self.devices = []
            self.show_error(_("Network unavailable"), str(error))
        self.device_selector.remove_all()
        active_index = 0
        for index, device in enumerate(self.devices):
            kind = _("Wi-Fi") if device.get_device_type() == NM.DeviceType.WIFI else _("Ethernet")
            self.device_selector.append_text(f"{device.get_iface()} · {kind}")
            if device.get_iface() == selected:
                active_index = index
        if self.devices:
            self.device_selector.set_active(active_index)
        else:
            self.device_status.set_text(_("No managed network interface detected."))
            self.save_button.set_sensitive(False)
            self.disconnect_button.set_sensitive(False)
        self.refresh_magicq()
        self.refresh_wifi()

    def current_device(self):
        index = self.device_selector.get_active()
        return self.devices[index] if 0 <= index < len(self.devices) else None

    @staticmethod
    def _profile_for(device):
        active = device.get_active_connection()
        if active is not None:
            return active.get_connection()
        available = device.get_available_connections()
        return available[0] if available else None

    def device_changed(self, _selector):
        device = self.current_device()
        if device is None:
            return
        profile = self._profile_for(device)
        connection_name = profile.get_id() if profile is not None else _("No saved connection")
        actual = device.get_ip4_config()
        actual_addresses = []
        if actual is not None:
            actual_addresses = [
                f"{actual.get_address(index).get_address()}/"
                f"{actual.get_address(index).get_prefix()}"
                for index in range(actual.get_num_addresses())]
        setting = profile.get_setting_ip4_config() if profile is not None else None
        method = setting.get_method() if setting is not None else "auto"
        configured = [
            f"{setting.get_address(index).get_address()}/"
            f"{setting.get_address(index).get_prefix()}"
            for index in range(setting.get_num_addresses())] if setting is not None else []
        secondary_configured = configured[1:] if method == "manual" else configured
        secondary = [item for item in actual_addresses if item in secondary_configured]
        primary = [item for item in actual_addresses if item not in secondary]
        details = [f"{device.get_iface()} · {connection_name}"]
        details.append(_("Primary IP: {address}").format(
            address=", ".join(primary) if primary else _("not assigned")))
        details.append(_("Secondary IP: {address}").format(
            address=", ".join(secondary) if secondary else _("not assigned")))
        self.device_status.set_text("\n".join(details))
        self.disconnect_button.set_sensitive(device.get_active_connection() is not None)
        self.save_button.set_sensitive(profile is not None)
        self.magicq_sync_button.set_sensitive(
            self.magicq_configuration is not None and
            device.get_device_type() == NM.DeviceType.ETHERNET)
        if profile is None:
            self.dhcp.set_active(True)
            for field in (self.address, self.prefix, self.gateway, self.dns):
                field.set_text("")
            return
        setting = profile.get_setting_ip4_config()
        method = setting.get_method() if setting is not None else "auto"
        self.manual.set_active(method == "manual")
        self.dhcp.set_active(method != "manual")
        address = setting.get_address(0) if setting is not None and setting.get_num_addresses() else None
        self.address.set_text(address.get_address() if address is not None else "")
        self.prefix.set_text(str(address.get_prefix()) if address is not None else "")
        gateway = setting.get_gateway() if setting is not None else None
        self.gateway.set_text(gateway or "")
        dns = [setting.get_dns(index) for index in range(setting.get_num_dns())] \
            if setting is not None else []
        self.dns.set_text(", ".join(dns))

    def method_changed(self, _button):
        enabled = self.manual.get_active()
        for field in (self.address, self.prefix, self.gateway, self.dns):
            field.set_sensitive(enabled)

    def save_ipv4(self, _button):
        device = self.current_device()
        profile = self._profile_for(device) if device is not None else None
        if profile is None:
            self.show_error(_("Network configuration"), _("No connection profile is available."))
            return
        try:
            setting = profile.get_setting_ip4_config()
            if setting is None:
                setting = NM.SettingIP4Config.new()
                profile.add_setting(setting)
            old_method = setting.get_method() or "auto"
            preserve_from = 1 if old_method == "manual" else 0
            secondary_addresses = [
                (setting.get_address(index).get_address(),
                 setting.get_address(index).get_prefix())
                for index in range(preserve_from, setting.get_num_addresses())]
            setting.clear_addresses()
            setting.clear_dns()
            setting.props.gateway = None
            if self.dhcp.get_active():
                setting.set_property(NM.SETTING_IP_CONFIG_METHOD, "auto")
            else:
                address = str(ipaddress.IPv4Address(self.address.get_text().strip()))
                prefix = int(self.prefix.get_text().strip())
                if not 0 <= prefix <= 32:
                    raise ValueError(_("Prefix must be between 0 and 32."))
                gateway_text = self.gateway.get_text().strip()
                gateway = str(ipaddress.IPv4Address(gateway_text)) if gateway_text else None
                dns_values = [value.strip() for value in self.dns.get_text().split(",") if value.strip()]
                dns_values = [str(ipaddress.IPv4Address(value)) for value in dns_values]
                setting.set_property(NM.SETTING_IP_CONFIG_METHOD, "manual")
                setting.add_address(NM.IPAddress.new(socket.AF_INET, address, prefix))
                setting.props.gateway = gateway
                for value in dns_values:
                    setting.add_dns(value)
            current = {
                (setting.get_address(index).get_address(),
                 setting.get_address(index).get_prefix())
                for index in range(setting.get_num_addresses())}
            for address, prefix in secondary_addresses:
                if (address, prefix) not in current:
                    setting.add_address(NM.IPAddress.new(
                        socket.AF_INET, address, prefix))
            profile.commit_changes(True, None)
            self._activate(profile, device)
        except Exception as error:
            self.show_error(_("Unable to save network configuration"), str(error))

    def refresh_magicq(self):
        try:
            result = self.runner.run(
                [self.paths.magicq_network, "inspect", "--json"], timeout=5)
            if result.returncode:
                raise ValueError(result.stderr.strip() or result.stdout.strip())
            self.magicq_configuration = json.loads(result.stdout)
            self.magicq_status.set_text(
                _("MagicQ address: {address}\nActive show: {show}").format(
                    address=self.magicq_configuration["cidr"],
                    show=os.path.basename(self.magicq_configuration["show"])))
        except Exception:
            self.magicq_configuration = None
            self.magicq_status.set_text(_(
                "No usable network address was found in the active MagicQ show."))
        device = self.current_device()
        self.magicq_sync_button.set_sensitive(
            self.magicq_configuration is not None and device is not None and
            device.get_device_type() == NM.DeviceType.ETHERNET)

    def sync_magicq(self, _button):
        device = self.current_device()
        if self.magicq_configuration is None or device is None:
            return
        dialog = Gtk.MessageDialog(
            transient_for=self.parent, modal=True, destroy_with_parent=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=_("Add the MagicQ network address?"))
        dialog.format_secondary_text(_(
            "{address} will be added to {interface} as a secondary address. "
            "The current Linux address and default gateway will remain unchanged.").format(
                address=self.magicq_configuration["cidr"],
                interface=device.get_iface()))
        prepare_dialog(dialog, self.parent)
        accepted = dialog.run() == Gtk.ResponseType.OK
        dialog.destroy()
        if not accepted:
            return
        self.magicq_sync_button.set_sensitive(False)
        self.background_command(
            ["pkexec", self.paths.magicq_network, "apply", device.get_iface()],
            _("MagicQ network synchronized"),
            callback=self.magicq_sync_finished, show_output=True)

    def magicq_sync_finished(self, _success):
        GLib.timeout_add_seconds(1, self._refresh_once)

    def _activate(self, profile, device, access_point=None):
        specific = access_point.get_path() if access_point is not None else None
        self.device_status.set_text(_("Applying network configuration…"))

        def finished(client, result, _data):
            try:
                client.activate_connection_finish(result)
                self.device_status.set_text(_("Network configuration applied."))
            except Exception as error:
                self.show_error(_("Unable to activate connection"), str(error))
            GLib.timeout_add_seconds(1, self._refresh_once)

        self._ensure_client().activate_connection_async(
            profile, device, specific, None, finished, None)

    def disconnect(self, _button):
        device = self.current_device()
        if device is None:
            return

        def finished(selected, result, _data):
            try:
                selected.disconnect_finish(result)
            except Exception as error:
                self.show_error(_("Unable to disconnect"), str(error))
            GLib.timeout_add_seconds(1, self._refresh_once)

        device.disconnect_async(None, finished, None)

    def scan_wifi(self, _button):
        wifi_devices = [device for device in self.devices
                        if device.get_device_type() == NM.DeviceType.WIFI]
        if not wifi_devices:
            self.show_error(_("Wi-Fi unavailable"), _("No managed Wi-Fi interface detected."))
            return

        pending = {device.get_iface() for device in wifi_devices}

        def finished(device, result, _data):
            try:
                device.request_scan_finish(result)
            except Exception:
                pass
            pending.discard(device.get_iface())
            if not pending:
                # A completed scan request means NetworkManager accepted the
                # request; access-point results arrive shortly afterwards.
                GLib.timeout_add_seconds(2, self._refresh_wifi_once)

        for device in wifi_devices:
            device.request_scan_async(None, finished, None)

    def _refresh_once(self):
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _refresh_wifi_once(self):
        self.refresh_wifi()
        return GLib.SOURCE_REMOVE

    @staticmethod
    def _ssid(access_point):
        value = access_point.get_ssid()
        return NM.utils_ssid_to_utf8(value.get_data()) if value is not None else ""

    @staticmethod
    def _wifi_security(access_point):
        flags = access_point.get_flags()
        wpa = access_point.get_wpa_flags()
        rsn = access_point.get_rsn_flags()
        secure = bool(flags or wpa or rsn)
        security_flags = getattr(NM, "80211ApSecurityFlags")
        enterprise = bool((wpa | rsn) & security_flags.KEY_MGMT_802_1X)
        legacy = secure and not bool(wpa or rsn)
        sae = bool(rsn & getattr(security_flags, "KEY_MGMT_SAE", 0))
        return secure, enterprise or legacy, sae

    def refresh_wifi(self):
        for child in self.wifi_list.get_children():
            self.wifi_list.remove(child)
        access_points = {}
        for device in self.devices:
            if device.get_device_type() != NM.DeviceType.WIFI:
                continue
            for access_point in device.get_access_points():
                ssid = self._ssid(access_point)
                if not ssid:
                    continue
                current = access_points.get(ssid)
                if current is None or access_point.get_strength() > current[1].get_strength():
                    access_points[ssid] = (device, access_point)
        if not access_points:
            empty = Gtk.Label(label=_("No Wi-Fi network detected."))
            empty.set_margin_top(12)
            empty.set_margin_bottom(12)
            self.wifi_list.add(empty)
        for ssid, (device, access_point) in sorted(
                access_points.items(), key=lambda item: item[1][1].get_strength(), reverse=True):
            secure, advanced_only, _sae = self._wifi_security(access_point)
            row = Gtk.Box(spacing=12)
            row.set_border_width(10)
            name = Gtk.Label(label=ssid)
            name.set_xalign(0)
            row.pack_start(name, True, True, 0)
            detail = Gtk.Label(label=f"{access_point.get_strength()}% · " +
                               (_("Protected") if secure else _("Open")))
            detail.get_style_context().add_class("section-subtitle")
            row.pack_start(detail, False, False, 0)
            connect = Gtk.Button(label=_("Connect"))
            connect.set_sensitive(not advanced_only)
            connect.set_tooltip_text(_(
                "Use Advanced for enterprise or legacy Wi-Fi."))
            connect.connect("clicked", self.connect_wifi, device, access_point)
            row.pack_start(connect, False, False, 0)
            self.wifi_list.add(row)
        self.wifi_list.show_all()

    def _saved_wifi(self, ssid):
        for profile in self._ensure_client().get_connections():
            setting = profile.get_setting_wireless()
            value = setting.get_ssid() if setting is not None else None
            if value is not None and NM.utils_ssid_to_utf8(value.get_data()) == ssid:
                return profile
        return None

    def connect_wifi(self, _button, device, access_point):
        ssid = self._ssid(access_point)
        saved = self._saved_wifi(ssid)
        if saved is not None:
            self._activate(saved, device, access_point)
            return
        secure, advanced_only, sae = self._wifi_security(access_point)
        if advanced_only:
            self.show_error(
                _("Advanced Wi-Fi"),
                _("Open Advanced to configure enterprise or legacy credentials."))
            return
        password = ""
        if secure:
            dialog = Gtk.Dialog(
                title=_("Connect to {network}").format(network=ssid),
                transient_for=self.parent, modal=True, destroy_with_parent=True)
            dialog.add_button(_("Cancel"), Gtk.ResponseType.CANCEL)
            connect = dialog.add_button(_("Connect"), Gtk.ResponseType.OK)
            connect.get_style_context().add_class("primary-button")
            entry = Gtk.Entry()
            entry.set_visibility(False)
            entry.set_placeholder_text(_("Wi-Fi password"))
            entry.set_activates_default(True)
            dialog.set_default_response(Gtk.ResponseType.OK)
            content = dialog.get_content_area()
            content.set_border_width(18)
            content.pack_start(entry, False, False, 0)
            dialog.show_all()
            prepare_dialog(dialog, self.parent)
            accepted = dialog.run() == Gtk.ResponseType.OK
            password = entry.get_text()
            dialog.destroy()
            if not accepted:
                return
            if len(password) < 8:
                self.show_error(_("Invalid Wi-Fi password"), _("The password must contain at least 8 characters."))
                return
        try:
            profile = NM.SimpleConnection.new()
            connection = NM.SettingConnection.new()
            connection.set_property(NM.SETTING_CONNECTION_ID, ssid)
            connection.set_property(NM.SETTING_CONNECTION_UUID, str(uuid.uuid4()))
            connection.set_property(NM.SETTING_CONNECTION_TYPE, "802-11-wireless")
            connection.set_property(NM.SETTING_CONNECTION_AUTOCONNECT, True)
            wireless = NM.SettingWireless.new()
            wireless.set_property(NM.SETTING_WIRELESS_SSID, access_point.get_ssid())
            profile.add_setting(connection)
            profile.add_setting(wireless)
            if secure:
                security = NM.SettingWirelessSecurity.new()
                security.set_property(
                    NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "sae" if sae else "wpa-psk")
                security.set_property(NM.SETTING_WIRELESS_SECURITY_PSK, password)
                profile.add_setting(security)
            ip4 = NM.SettingIP4Config.new()
            ip4.set_property(NM.SETTING_IP_CONFIG_METHOD, "auto")
            profile.add_setting(ip4)
            ip6 = NM.SettingIP6Config.new()
            ip6.set_property(NM.SETTING_IP_CONFIG_METHOD, "auto")
            profile.add_setting(ip6)
        except Exception as error:
            self.show_error(_("Unable to prepare Wi-Fi connection"), str(error))
            return

        self.device_status.set_text(_("Connecting to {network}…").format(network=ssid))

        def finished(client, result, _data):
            try:
                client.add_and_activate_connection_finish(result)
            except Exception as error:
                self.show_error(_("Unable to connect to Wi-Fi"), str(error))
            GLib.timeout_add_seconds(1, self._refresh_once)

        self._ensure_client().add_and_activate_connection_async(
            profile, device, access_point.get_path(), None, finished, None)
