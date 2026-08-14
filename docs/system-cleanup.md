# Pulizia del sistema Ubuntu

Wasalight prepara una postazione fisica dedicata a MagicQ, non un server cloud
generico. Al termine della configurazione l'installer rimuove soltanto i
componenti che non servono all'appliance e che sono stati verificati sul disco
in uso.

## Pacchetti gestiti

| Pacchetto | Funzione originale | Comportamento Wasalight |
| --- | --- | --- |
| `cloud-init` | Configurazione iniziale di istanze cloud | Rimosso per impostazione predefinita; `--keep-cloud-init` lo conserva |
| `multipath-tools` | Accesso ridondante a storage SAN | Rimosso solo se root e `/data` non dipendono da un dispositivo `mpath` |
| `open-iscsi` | Accesso a dischi iSCSI di rete | Rimosso solo se root e `/data` non dipendono dal trasporto iSCSI |
| `pollinate` | Seed di entropia, soprattutto per istanze cloud | Rimosso sulla postazione dedicata |
| `os-prober` | Ricerca altri sistemi operativi per GRUB | Rimosso: Wasalight è un’appliance a sistema singolo e dichiara `GRUB_DISABLE_OS_PROBER=true` |

Il controllo risale la gerarchia dei dispositivi con `lsblk`. Un volume LVM
sotto `/dev/mapper`, come quelli usati normalmente da Wasalight, ha tipo `lvm`
e non viene confuso con un volume multipath di tipo `mpath`.

La pulizia non rimuove LVM, NetworkManager, Xorg, Openbox, udev, OpenSSH usato
dal controllo remoto, `needrestart` o le dipendenze grafiche di MagicQ.
Le librerie XCB richieste dal plugin Qt di MagicQ sono elencate esplicitamente
tra le dipendenze dell'appliance, così APT non può considerarle superflue.

Dopo il passaggio definitivo a NetworkManager, Wasalight disabilita anche
`systemd-networkd` e `systemd-networkd-wait-online`. Lasciarli attivi senza
interfacce di competenza produce soltanto un timeout e una falsa unità fallita;
NetworkManager rimane l’unico gestore della rete della console.

## Ordine delle operazioni APT

L’installer evita che i timer APT e `unattended-upgrades` lavorino in parallelo,
quindi calcola l’elenco dei pacchetti richiesti dalla configurazione scelta. Se
sono già tutti installati salta sia `apt-get update` sia `apt-get install`. Se ne
manca almeno uno aggiorna gli indici e installa soltanto i pacchetti mancanti.
`apt-get update` scarica soltanto metadati: non aggiorna i programmi presenti.

Prima di installare lo stack Wasalight vengono rimossi i componenti certamente
estranei all’appliance: Snap, stampa, Bluetooth, ModemManager, Avahi, Whoopsie,
Apport e aggiornamenti automatici. Non viene ancora eseguito `autoremove`, così
una dipendenza necessaria a Wasalight non viene eliminata e poi scaricata di
nuovo.

Dopo l’installazione di Wasalight e MagicQ vengono eseguiti i controlli reali
su multipath e iSCSI e la pulizia dei componenti cloud/SAN. Soltanto a questo
punto l’installer esegue un unico `apt-get autoremove --purge`, seguito da
`apt-get clean`. In questo modo APT conosce già l’insieme definitivo dei
pacchetti dell’appliance.

## Messaggio QEMU dopo APT

Wasalight non installa QEMU. Dopo un'operazione APT, `needrestart` può mostrare
un messaggio simile a:

```text
No VM guests are running outdated hypervisor (qemu) binaries on this host.
```

Il messaggio significa che il controllo non ha trovato guest virtuali da
riavviare. Non è un errore, non prova che QEMU sia installato e non richiede
alcuna rimozione.

Per verificare esplicitamente l'assenza dei pacchetti principali:

```bash
dpkg -l qemu-guest-agent qemu-system-x86 qemu-utils qemu-block-extra
```

## Verifica dopo l'installazione

Eseguire in MAINTENANCE mode:

```bash
wasalight-status
systemctl --failed --no-pager
findmnt / /data
lsblk
```

`systemctl --failed` deve riportare zero unità fallite. Root e `/data` devono
continuare a riferirsi ai volumi previsti.

Per vedere senza modificare il sistema cosa eliminerebbe APT:

```bash
apt-get -s autoremove --purge
```

Non usare comandi di rimozione generici basati su wildcard: l'installer elimina
nomi espliciti solo dopo i controlli sullo storage.

## Ripristino di un componente

Se l'hardware viene successivamente collegato a storage iSCSI o multipath,
entrare in MAINTENANCE mode e reinstallare prima il componente necessario:

```bash
sudo apt update
sudo apt install open-iscsi multipath-tools
```

Configurare e verificare lo storage prima di riavviare in SHOW mode. Una nuova
esecuzione di Wasalight conserverà automaticamente i pacchetti quando root o
`/data` risultano effettivamente dipendenti da quel tipo di storage.
