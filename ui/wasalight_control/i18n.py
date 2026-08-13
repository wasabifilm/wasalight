"""Localization support shared by all Wasalight Control pages."""

import gettext
import os
import tempfile


DOMAIN = "wasalight-control"
DEFAULT_LOCALE_DIR = "/usr/local/share/locale"
DEFAULT_LANGUAGE_FILE = "/data/system/control/language"
SUPPORTED_LANGUAGES = ("auto", "en", "it")

_translation = gettext.NullTranslations()
_language = "auto"


def _read_preference(language_file):
    override = os.environ.get("WASALIGHT_CONTROL_LANGUAGE", "").strip()
    if override:
        return override
    try:
        with open(language_file, encoding="utf-8") as source:
            return source.read().strip()
    except OSError:
        return "auto"


def configure(*, language_file=DEFAULT_LANGUAGE_FILE,
              locale_dir=DEFAULT_LOCALE_DIR):
    """Select the persisted language, falling back to the session locale."""
    global _language, _translation
    requested = _read_preference(language_file)
    _language = requested if requested in SUPPORTED_LANGUAGES else "auto"
    languages = None if _language == "auto" else [_language]
    _translation = gettext.translation(
        DOMAIN, localedir=locale_dir, languages=languages, fallback=True)
    return _language


def current_language():
    return _language


def save_language(language, *, language_file=DEFAULT_LANGUAGE_FILE):
    """Persist a validated preference atomically for the next Control launch."""
    if language not in SUPPORTED_LANGUAGES:
        raise ValueError(f"unsupported language: {language}")
    directory = os.path.dirname(language_file) or "."
    os.makedirs(directory, mode=0o750, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".control-language-", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as destination:
            destination.write(f"{language}\n")
        os.chmod(temporary, 0o640)
        os.replace(temporary, language_file)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def gettext_message(message):
    return _translation.gettext(message)


def ngettext(singular, plural, count):
    return _translation.ngettext(singular, plural, count)


_ = gettext_message


configure(
    language_file=os.environ.get(
        "WASALIGHT_CONTROL_LANGUAGE_FILE", DEFAULT_LANGUAGE_FILE),
    locale_dir=os.environ.get(
        "WASALIGHT_CONTROL_LOCALE_DIR", DEFAULT_LOCALE_DIR),
)
