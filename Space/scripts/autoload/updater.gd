extends Node




signal update_check_complete(has_update: bool, latest_version: String)
signal download_progress(percent: float)
signal download_complete(success: bool, message: String)

const GITHUB_REPO: String = "fables-of-yig/spacegameone"
const RELEASES_URL: String = "https://api.github.com/repos/%s/releases/latest" % GITHUB_REPO
const PCK_ASSET_NAME: String = "MVPlusEditor.pck"
const VERSION_FILE: String = "res://version.txt"
const CHECK_TIMEOUT: float = 20.0
const DOWNLOAD_TIMEOUT: float = 300.0

enum State{IDLE, CHECKING, UPDATE_AVAILABLE, DOWNLOADING, DONE_SUCCESS, DONE_NO_UPDATE, DONE_ERROR}

var state: State = State.IDLE
var current_version: String = "0.0.0001"
var latest_version: String = ""
var latest_pck_url: String = ""
var download_percent: float = 0.0
var error_message: String = ""
var result_message: String = ""

var _check_request: HTTPRequest = null
var _download_request: HTTPRequest = null
var _download_path: String = ""
var _state_timer: float = 0.0
var _restart_countdown: float = -1.0

func _ready():
    process_mode = PROCESS_MODE_ALWAYS
    _load_current_version()
    _log("Ready. Version: %s" % current_version)

func _log(msg: String):
    var full = "[Updater] %s" % msg
    print(full)

    if not OS.has_feature("editor"):
        var log_path = OS.get_executable_path().get_base_dir().path_join("updater_log.txt")
        var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
        if not f:
            f = FileAccess.open(log_path, FileAccess.WRITE)
        if f:
            f.seek_end()
            f.store_string("%s  %s\n" % [Time.get_datetime_string_from_system(), msg])
            f.close()

func _load_current_version():


    if not OS.has_feature("editor"):
        var exe_dir = OS.get_executable_path().get_base_dir()
        var ext_path = exe_dir.path_join("version.txt")
        if FileAccess.file_exists(ext_path):
            var f = FileAccess.open(ext_path, FileAccess.READ)
            if f:
                current_version = f.get_as_text().strip_edges()
                f.close()
                _log("Version from exe dir: %s" % current_version)
                return

    if FileAccess.file_exists("user://version.txt"):
        var f = FileAccess.open("user://version.txt", FileAccess.READ)
        if f:
            var ver = f.get_as_text().strip_edges()
            f.close()
            if ver != "":
                current_version = ver
                _log("Version from user://: %s" % current_version)
                return

    if FileAccess.file_exists(VERSION_FILE):
        var f = FileAccess.open(VERSION_FILE, FileAccess.READ)
        if f:
            current_version = f.get_as_text().strip_edges()
            f.close()
    _log("Version from res://: %s" % current_version)

func check_for_update():
    if state == State.CHECKING or state == State.DOWNLOADING:
        _log("Already busy (state=%d), ignoring check request" % state)
        return
    state = State.CHECKING
    _state_timer = 0.0
    error_message = ""
    result_message = "Checking for updates..."
    _log("Starting update check -> %s" % RELEASES_URL)

    if _check_request:
        _check_request.queue_free()
    _check_request = HTTPRequest.new()
    _check_request.timeout = 15.0
    add_child(_check_request)
    _check_request.request_completed.connect(_on_check_complete)

    var headers = ["User-Agent: Abysson-Updater", "Accept: application/vnd.github.v3+json"]
    var err = _check_request.request(RELEASES_URL, headers)
    if err != OK:
        _log("Failed to send request, error code: %d" % err)
        _fail("Failed to send request (error %d)" % err)

func _on_check_complete(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
    _log("Check complete: result=%d  http=%d  body_size=%d" % [result, response_code, body.size()])
    if _check_request:
        _check_request.queue_free()
        _check_request = null

    if result != HTTPRequest.RESULT_SUCCESS:
        var result_names = ["Success", "ChunkedBodySizeMismatch", "CantConnect", "CantResolve", "ConnectionError", "TlsHandshakeError", "NoResponse", "BodySizeLimitExceeded", "BodyDecompFailed", "RequestFailed", "DownloadFileCantOpen", "DownloadFileWriteError", "RedirectLimitReached", "Timeout"]
        var rname = result_names[result] if result < result_names.size() else str(result)
        _fail("Connection failed: %s" % rname)
        return

    if response_code != 200:
        _fail("GitHub API error (HTTP %d)" % response_code)
        return

    var json = JSON.new()
    if json.parse(body.get_string_from_utf8()) != OK:
        _fail("Failed to parse release info")
        return

    var data: Dictionary = json.data
    latest_version = str(data.get("tag_name", "")).trim_prefix("v")
    var assets: Array = data.get("assets", [])


    latest_pck_url = ""
    for asset in assets:
        var aname = str(asset.get("name", ""))
        if aname == PCK_ASSET_NAME or aname.ends_with(".pck"):

            latest_pck_url = str(asset.get("url", ""))
            if latest_pck_url == "":
                latest_pck_url = str(asset.get("browser_download_url", ""))
            break

    _log("Latest: %s  Current: %s  PCK URL: %s" % [latest_version, current_version, latest_pck_url])

    if latest_version == "" or latest_version == current_version:
        state = State.DONE_NO_UPDATE
        result_message = "Already on latest version (%s)" % current_version
        update_check_complete.emit(false, latest_version)
        return

    if _is_newer(latest_version, current_version):
        if latest_pck_url == "":
            _fail("New version %s found but no .pck in release" % latest_version)
        else:
            state = State.UPDATE_AVAILABLE
            result_message = "Update available: %s -> %s" % [current_version, latest_version]
            _log(result_message)
            update_check_complete.emit(true, latest_version)
    else:
        state = State.DONE_NO_UPDATE
        result_message = "Already on latest version (%s)" % current_version
        update_check_complete.emit(false, latest_version)

func _is_newer(remote: String, local: String) -> bool:
    var r_parts = remote.split(".")
    var l_parts = local.split(".")
    for i in maxi(r_parts.size(), l_parts.size()):
        var r = int(r_parts[i]) if i < r_parts.size() else 0
        var l = int(l_parts[i]) if i < l_parts.size() else 0
        if r > l:
            return true
        elif r < l:
            return false
    return false

func start_download():
    if state != State.UPDATE_AVAILABLE or latest_pck_url == "":
        return
    state = State.DOWNLOADING
    _state_timer = 0.0
    download_percent = 0.0
    result_message = "Downloading update..."


    _download_path = _get_pck_path()
    if _download_path == "":
        _fail_download("Could not determine .pck location")
        return

    _log("Downloading to: %s" % _download_path)
    _log("From URL: %s" % latest_pck_url)

    if _download_request:
        _download_request.queue_free()
    _download_request = HTTPRequest.new()
    _download_request.timeout = DOWNLOAD_TIMEOUT
    _download_request.download_file = _download_path + ".tmp"
    _download_request.use_threads = true

    _download_request.max_redirects = 0
    add_child(_download_request)
    _download_request.request_completed.connect(_on_download_redirect_or_complete)

    var headers = ["User-Agent: Abysson-Updater", "Accept: application/octet-stream"]
    var err = _download_request.request(latest_pck_url, headers)
    if err != OK:
        _fail_download("Failed to start download (error %d)" % err)

func _on_download_redirect_or_complete(result: int, response_code: int, headers: PackedStringArray, _body: PackedByteArray):
    _log("Download response: result=%d  http=%d" % [result, response_code])
    if _download_request:
        _download_request.queue_free()
        _download_request = null


    if response_code == 302 or response_code == 301:
        var location = ""
        for h in headers:
            if h.to_lower().begins_with("location:"):
                location = h.substr(h.find(":") + 1).strip_edges()
                break
        if location == "":
            _fail_download("Got redirect but no Location header")
            return
        _log("Following redirect (no auth) -> %s" % location.substr(0, 80))

        _download_request = HTTPRequest.new()
        _download_request.timeout = DOWNLOAD_TIMEOUT
        _download_request.download_file = _download_path + ".tmp"
        _download_request.use_threads = true
        add_child(_download_request)
        _download_request.request_completed.connect(_on_download_complete)
        var err = _download_request.request(location, ["User-Agent: Abysson-Updater"])
        if err != OK:
            _fail_download("Failed to follow redirect (error %d)" % err)
        return


    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
        _finalize_download()
        return

    _fail_download("Download failed (HTTP %d, result %d)" % [response_code, result])

func _on_download_complete(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
    _log("Final download: result=%d  http=%d" % [result, response_code])
    if _download_request:
        _download_request.queue_free()
        _download_request = null

    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        var tmp_path = _download_path + ".tmp"
        if FileAccess.file_exists(tmp_path):
            DirAccess.remove_absolute(tmp_path)
        _fail_download("Download failed (HTTP %d)" % response_code if response_code > 0 else "Download connection failed")
        return

    _finalize_download()

func _finalize_download():
    var tmp_path = _download_path + ".tmp"


    if not FileAccess.file_exists(tmp_path):
        _fail_download("Downloaded file not found at %s" % tmp_path)
        return

    var f = FileAccess.open(tmp_path, FileAccess.READ)
    var file_size = f.get_length() if f else 0
    if f:
        f.close()
    _log("Downloaded file size: %d bytes" % file_size)
    if file_size < 1000:
        DirAccess.remove_absolute(tmp_path)
        _fail_download("Downloaded file too small (%d bytes) — may be an error page" % file_size)
        return


    var backup_path = _download_path + ".backup"
    if FileAccess.file_exists(backup_path):
        DirAccess.remove_absolute(backup_path)
    if FileAccess.file_exists(_download_path):
        DirAccess.rename_absolute(_download_path, backup_path)

    var rename_err = DirAccess.rename_absolute(tmp_path, _download_path)
    if rename_err != OK:

        if FileAccess.file_exists(backup_path):
            DirAccess.rename_absolute(backup_path, _download_path)
        _fail_download("Failed to replace .pck file (error %d)" % rename_err)
        return


    _write_version(latest_version)


    if FileAccess.file_exists(backup_path):
        DirAccess.remove_absolute(backup_path)

    state = State.DONE_SUCCESS
    current_version = latest_version
    download_percent = 100.0
    var size_mb = file_size / (1024.0 * 1024.0)
    result_message = "Updated to %s (%.1f MB). Restarting in 5..." % [latest_version, size_mb]
    _log(result_message)
    _restart_countdown = 5.0
    download_complete.emit(true, result_message)

func _process(delta: float):

    if _restart_countdown > 0.0:
        _restart_countdown -= delta
        var secs = ceili(_restart_countdown)
        result_message = "Updated to %s. Restarting in %d..." % [current_version, secs]
        if _restart_countdown <= 0.0:
            _log("Auto-restarting after update")
            OS.set_restart_on_exit(true)
            get_tree().quit()
            return

    if state == State.DOWNLOADING and _download_request:
        var body_size = _download_request.get_body_size()
        var downloaded = _download_request.get_downloaded_bytes()
        if body_size > 0:
            download_percent = float(downloaded) / float(body_size) * 100.0
        download_progress.emit(download_percent)


    if state == State.CHECKING or state == State.DOWNLOADING:
        _state_timer += delta
        var timeout_limit = CHECK_TIMEOUT if state == State.CHECKING else DOWNLOAD_TIMEOUT + 30.0
        if _state_timer > timeout_limit:
            _log("TIMEOUT: stuck in state %d for %.0fs, force-failing" % [state, _state_timer])
            if _check_request:
                _check_request.queue_free()
                _check_request = null
            if _download_request:
                _download_request.queue_free()
                _download_request = null
            if state == State.CHECKING:
                _fail("Timed out — check internet/firewall")
            else:
                var tmp_path = _download_path + ".tmp"
                if FileAccess.file_exists(tmp_path):
                    DirAccess.remove_absolute(tmp_path)
                _fail_download("Download timed out")

func _fail(msg: String):
    state = State.DONE_ERROR
    error_message = msg
    result_message = msg
    _log("ERROR: %s" % msg)
    update_check_complete.emit(false, "")

func _fail_download(msg: String):
    state = State.DONE_ERROR
    error_message = msg
    result_message = msg
    _log("DOWNLOAD ERROR: %s" % msg)
    download_complete.emit(false, msg)

func _get_pck_path() -> String:

    if OS.has_feature("editor"):
        return ProjectSettings.globalize_path("res://").path_join(PCK_ASSET_NAME)
    var exe_path = OS.get_executable_path()
    var exe_dir = exe_path.get_base_dir()

    var exe_name = exe_path.get_file().get_basename()
    var pck_path = exe_dir.path_join(exe_name + ".pck")
    if FileAccess.file_exists(pck_path):
        return pck_path

    pck_path = exe_dir.path_join(PCK_ASSET_NAME)
    if FileAccess.file_exists(pck_path):
        return pck_path

    return exe_dir.path_join(PCK_ASSET_NAME)

func _write_version(ver: String):

    if not OS.has_feature("editor"):
        var exe_dir = OS.get_executable_path().get_base_dir()
        var ver_path = exe_dir.path_join("version.txt")
        var f = FileAccess.open(ver_path, FileAccess.WRITE)
        if f:
            f.store_string(ver)
            f.close()

    var f2 = FileAccess.open("user://version.txt", FileAccess.WRITE)
    if f2:
        f2.store_string(ver)
        f2.close()

func get_display_version() -> String:
    return current_version
