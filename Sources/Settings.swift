import Carbon.HIToolbox
import Cocoa

let SOURCE_LANGUAGE = "en"
let TARGET_LANGUAGE_KEY = "targetLanguage"
let DEFAULT_TARGET_LANGUAGE = "es"
// Google's codes where they differ from the dictionaries' language identifiers.
let GOOGLE_LANGUAGE_CODES = ["zh-Hans": "zh-CN", "zh-Hant": "zh-TW", "zh-Hant-HK": "zh-TW", "yue-Hant": "yue"]
let TRANSLATION_LANGUAGES_SETTINGS = "System Settings → General → Language & Region → Translation Languages"
// Searched for in a dictionary that isn't downloaded yet, which makes macOS download it.
let DOWNLOAD_TRIGGER_WORD = "hello"
let WARNING_SYMBOL = "exclamationmark.triangle"
let HTTP_TOO_MANY_REQUESTS = 429
// Google usually answers in 0.1–0.3 s; a stalled network hands the text to Apple Translation after this.
let GOOGLE_TIMEOUT: TimeInterval = 1
let INDEX_LANGUAGE_KEY = "DCSDictionaryIndexLanguage"
let DESCRIPTION_LANGUAGE_KEY = "DCSDictionaryDescriptionLanguage"
let ENTRY_XHTML_VERSION = 0
let MAX_DICTIONARY_RECORDS = 3
let MAIN_TRANSLATION_TERMS = 2
let TRAILING_PUNCTUATION = CharacterSet(charactersIn: ",;:/ ")
// Separators and grammar labels (impf, pf, m pl) the dictionary adds for display.
let HIDDEN_ENTRY_CLASSES: Set<String> = ["gp", "tgr"]

struct SpeechSpeed {
    let title: String
    let rate: Float
}

// YouTube's playback speeds. Applied when playing, with the pitch kept: the Core ML model has no speed condition.
let SPEECH_SPEEDS = [
    SpeechSpeed(title: "0.25", rate: 0.25),
    SpeechSpeed(title: "0.5", rate: 0.5),
    SpeechSpeed(title: "0.75", rate: 0.75),
    SpeechSpeed(title: "Normal", rate: 1),
    SpeechSpeed(title: "1.25", rate: 1.25),
    SpeechSpeed(title: "1.5", rate: 1.5),
    SpeechSpeed(title: "1.75", rate: 1.75),
    SpeechSpeed(title: "2", rate: 2),
]
let DEFAULT_SPEED_INDEX = 3
let SPEED_KEY = "speed"
let SPEED_SAMPLE = "This is how fast I speak."
let VOICE_KEY = "voice"
let VOICE_SAMPLE = "Hello, this is how I sound."

let PHONON_VOICES = ["Harper", "Hadley", "Everly", "Maeve", "Edwin", "Spencer"]
// The model folder build.sh puts in the app's Resources, and its copy in Application Support,
// where Core ML compiles it on the first launch.
let MODELS_FOLDER = "Models"
// One sample to schedule after an utterance: its playback marks the end of the speech.
let END_MARKER_SAMPLES = 1
let PREPARING_VOICE_NOTE = "Preparing the voice: the first launch takes a few seconds."

let HOTKEY_KEY_CODE = UInt32(kVK_ANSI_T)
let HOTKEY_MODIFIERS = UInt32(controlKey | optionKey)
let HOTKEY_LABEL = "⌃⌥T"
let HOTKEY_SIGNATURE: OSType = 0x5750_4F50 // "WPOP"

let DOUBLE_TAP_MODIFIER = NSEvent.ModifierFlags.option
let DOUBLE_TAP_LABEL = "⌥⌥"
let TRACKED_MODIFIERS: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
let TAP_MAX_DURATION: TimeInterval = 0.3
let DOUBLE_TAP_INTERVAL: TimeInterval = 0.4

let MAX_SELECTION_LENGTH = 500
let COPY_TIMEOUT: TimeInterval = 0.4
let COPY_POLL_INTERVAL: TimeInterval = 0.02
let POPUP_LIFETIME: TimeInterval = 10
let POPUP_WIDTH: CGFloat = 340
let POPUP_PADDING: CGFloat = 14
let POPUP_HEADER_SPACING: CGFloat = 6
// Longer selections are phrases, set in this size instead of the style's word size.
let POPUP_PHRASE_LENGTH = 30
let POPUP_PHRASE_SIZE: CGFloat = 17
let POPUP_CURSOR_OFFSET: CGFloat = 16
let POPUP_QUICK_FADE: TimeInterval = 0.12
let POPUP_SLOW_FADE: TimeInterval = 0.35
let POPUP_FADE_OUT: TimeInterval = 0.15
let POPUP_FADE_OUT_KEY = "fadeOut"
let POPUP_FADE_IN_KEY = "fadeIn"
let MAX_DICTIONARY_TERMS = 6
let ESCAPE_KEY_CODE = UInt16(kVK_Escape)

let SUPPORT_FOLDER = "Word Popup"
let HISTORY_FILE = "history.json"
let HISTORY_WINDOW_SIZE = NSSize(width: 720, height: 560)
let HISTORY_ROW_HEIGHT: CGFloat = 40
let HISTORY_SPACING: CGFloat = 8
let HISTORY_CELL_INSET: CGFloat = 4
let HISTORY_COLUMNS: [(id: String, title: String, width: CGFloat)] = [
    ("word", "Word", 170),
    ("translation", "Translation", 330),
    ("count", "Times", 50),
    ("date", "Last looked up", 140),
]
let DELETE_KEY_CODES: Set<UInt16> = [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)]
