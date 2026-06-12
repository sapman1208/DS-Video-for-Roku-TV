sub init()
      ' Default credentials — overridden by registry if previously saved
      m.nasAddress = ""
      m.nasPort    = "5001"
      m.useHttps   = true
      m.username   = ""
      m.password   = ""
      m.activeField = ""
      m.focusIndex = 0
      m.blockFirstOk = false
      m.pendingKeyboardFocus = 0
      m.pendingKeyboardClose = false

      m.rowYs = [190, 290, 390, 490, 590, 740]

      m.top.observeField("keyInput", "onKeyInput")
      m.top.observeField("settingsMode", "onSettingsModeChanged")
      m.top.findNode("keyboardFocusTimer").observeField("fire", "onKeyboardFocusTimer")

      loadSavedCredentials()
      updateAllValues()
      setHighlight(0)
      if m.top.settingsMode = true then applySettingsMode()
  end sub

sub onSettingsModeChanged(event as object)
    if event.getData() = true
        applySettingsMode()
    else
        m.blockFirstOk = false
        m.top.findNode("row6value").text = "Login"
    end if
end sub

sub applySettingsMode()
    m.blockFirstOk = true
    m.top.findNode("row6value").text = "Save"
    showStatus("Edit settings, then choose Save. Press Back to return.", false)
end sub

sub loadSavedCredentials()
      reg = createObject("roRegistrySection", "DSVideo")
      if reg.exists("nasAddress") then m.nasAddress = readProtectedSetting(reg, "nasAddress")
      if reg.exists("nasPort") then m.nasPort = readProtectedSetting(reg, "nasPort")
      if reg.exists("useHttps") then m.useHttps = (reg.read("useHttps") = "true")
      if reg.exists("username") then m.username = readProtectedSetting(reg, "username")
      if reg.exists("password") then m.password = readProtectedSetting(reg, "password")
  end sub

sub saveCredentials()
      reg = createObject("roRegistrySection", "DSVideo")
      writeProtectedSetting(reg, "nasAddress", m.nasAddress)
      writeProtectedSetting(reg, "nasPort", m.nasPort)
      if m.useHttps
          reg.write("useHttps", "true")
      else
          reg.write("useHttps", "false")
      end if
      writeProtectedSetting(reg, "username", m.username)
      writeProtectedSetting(reg, "password", m.password)
      reg.flush()
  end sub

sub updateAllValues()
    if m.nasAddress = ""
        m.top.findNode("row0value").text = "(not set)"
    else
        m.top.findNode("row0value").text = m.nasAddress
    end if
    m.top.findNode("row1value").text = m.nasPort
    if m.useHttps
        m.top.findNode("row2value").text = "HTTPS  (OK to toggle)"
    else
        m.top.findNode("row2value").text = "HTTP  (OK to toggle)"
    end if
    m.top.findNode("row3value").text = m.username
    if m.password = ""
        m.top.findNode("row4value").text = "(not set)"
    else
        m.top.findNode("row4value").text = "••••••••"
    end if
end sub

function readProtectedSetting(reg as object, key as string) as string
    if reg = invalid then return ""
    if not reg.exists(key) then return ""
    return unprotectSetting(reg.read(key), key)
end function

sub writeProtectedSetting(reg as object, key as string, value as string)
    if reg = invalid then return
    reg.write(key, protectSetting(value, key))
end sub

function protectSetting(value as dynamic, key as string) as string
    if value = invalid then return ""
    if type(value) <> "roString" and type(value) <> "String" then return ""
    if value = "" then return ""
    secret = settingSecret(key)
    out = "enc:v1:"
    i = 1
    while i <= len(value)
        code = asc(mid(value, i, 1))
        secretIndex = ((i - 1) mod len(secret)) + 1
        salt = asc(mid(secret, secretIndex, 1)) + ((i * 17) mod 251)
        encoded = (code + salt) mod 256
        out = out + hexByte(encoded)
        i = i + 1
    end while
    return out
end function

function unprotectSetting(value as dynamic, key as string) as string
    if value = invalid then return ""
    if type(value) <> "roString" and type(value) <> "String" then return ""
    prefix = "enc:v1:"
    if left(value, len(prefix)) <> prefix then return value
    hexText = mid(value, len(prefix) + 1)
    secret = settingSecret(key)
    out = ""
    i = 1
    charIndex = 1
    while i <= len(hexText) - 1
        encoded = hexPairValue(mid(hexText, i, 2))
        secretIndex = ((charIndex - 1) mod len(secret)) + 1
        salt = asc(mid(secret, secretIndex, 1)) + ((charIndex * 17) mod 251)
        decoded = encoded - (salt mod 256)
        while decoded < 0
            decoded = decoded + 256
        end while
        out = out + chr(decoded)
        i = i + 2
        charIndex = charIndex + 1
    end while
    return out
end function

function settingSecret(key as string) as string
    return "DSVideo:Roku:" + key + ":2026"
end function

function hexByte(value as integer) as string
    high = int(value / 16)
    low = value - (high * 16)
    return hexDigit(high) + hexDigit(low)
end function

function hexDigit(value as integer) as string
    digits = "0123456789abcdef"
    return mid(digits, value + 1, 1)
end function

function hexPairValue(pair as string) as integer
    if len(pair) < 2 then return 0
    return hexDigitValue(left(pair, 1)) * 16 + hexDigitValue(mid(pair, 2, 1))
end function

function hexDigitValue(ch as string) as integer
    code = asc(lcase(ch))
    if code >= 48 and code <= 57 then return code - 48
    if code >= 97 and code <= 102 then return code - 87
    return 0
end function

sub setHighlight(idx as integer)
    m.focusIndex = idx
    yPos = m.rowYs[idx]
    m.top.findNode("rowHighlight").translation = [580, yPos]
    if idx = 5
        m.top.findNode("rowHighlight").color = "#A91F2A"
    else
        m.top.findNode("rowHighlight").color = "#F05A63"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    return handleKey(key)
end function

function handleKey(key as string) as boolean
    if key = "down"
        if m.focusIndex < 5
            setHighlight(m.focusIndex + 1)
        end if
        return true
    end if

    if key = "up"
        if m.focusIndex > 0
            setHighlight(m.focusIndex - 1)
        end if
        return true
    end if

    if key = "OK"
        if m.blockFirstOk
            m.blockFirstOk = false
            return true
        end if
        activateRow(m.focusIndex)
        return true
    end if

    return false
end function

sub activateRow(idx as integer)
    if idx = 0
        m.activeField = "address"
        showKeyboard("NAS Address (IP or hostname)", m.nasAddress)
    else if idx = 1
        m.activeField = "port"
        showKeyboard("Port", m.nasPort)
    else if idx = 2
        ' Toggle HTTP / HTTPS
        m.useHttps = not m.useHttps
        if m.useHttps
            m.top.findNode("row2value").text = "HTTPS  (OK to toggle)"
            if m.nasPort = "5000" then m.nasPort = "5001"
        else
            m.top.findNode("row2value").text = "HTTP  (OK to toggle)"
            if m.nasPort = "5001" then m.nasPort = "5000"
        end if
        m.top.findNode("row1value").text = m.nasPort
    else if idx = 3
        m.activeField = "username"
        showKeyboard("Username", m.username)
    else if idx = 4
        m.activeField = "password"
        showKeyboard("Password", "")
    else if idx = 5 and m.top.settingsMode = true
        saveCredentials()
        showStatus("Settings saved. Press Back to return.", false)
    else if idx = 5
        doLogin()
    end if
end sub

sub showKeyboard(title as string, currentText as string)
    dialog = createObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = title
    dialog.text = currentText
    dialog.buttons = ["OK", "Cancel"]
    dialog.observeField("buttonSelected", "onKeyboardDone")
    m.currentDialog = dialog
    m.top.getScene().dialog = dialog
end sub

sub onKeyboardDone(event as object)
    if m.currentDialog = invalid
        m.activeField = ""
        queueKeyboardFocusRestore(0)
        return
    end if
    btnIdx = event.getData()
    entered = m.currentDialog.text
    completedField = m.activeField
    print "LOGIN_KEYBOARD_DONE button="; btnIdx; " field="; completedField

    if btnIdx = 0
        if m.activeField = "address"
            m.nasAddress = entered
            if entered = ""
                m.top.findNode("row0value").text = "(not set)"
            else
                m.top.findNode("row0value").text = entered
            end if
        else if m.activeField = "port"
            if entered <> "" then m.nasPort = entered
            m.top.findNode("row1value").text = m.nasPort
        else if m.activeField = "username"
            if entered <> "" then m.username = entered
            m.top.findNode("row3value").text = m.username
        else if m.activeField = "password"
            m.password = entered
            if entered = ""
                m.top.findNode("row4value").text = "(not set)"
            else
                m.top.findNode("row4value").text = "••••••••"
            end if
        end if
    end if

    m.activeField = ""
    m.pendingKeyboardClose = true
    if completedField = "address"
        queueKeyboardFocusRestore(0)
    else
        queueKeyboardFocusRestore(m.focusIndex)
    end if
end sub

sub queueKeyboardFocusRestore(rowIndex as integer)
    if rowIndex < 0 then rowIndex = 0
    if rowIndex > 5 then rowIndex = 5
    m.pendingKeyboardFocus = rowIndex
    timer = m.top.findNode("keyboardFocusTimer")
    if timer <> invalid
        timer.control = "stop"
        timer.control = "start"
    else
        restoreKeyboardFocus(rowIndex)
    end if
end sub

sub onKeyboardFocusTimer(event as object)
    print "LOGIN_KEYBOARD_REFOCUS row="; m.pendingKeyboardFocus
    if m.pendingKeyboardClose = true
        print "LOGIN_KEYBOARD_CLOSE_DELAYED"
        if m.currentDialog <> invalid
            m.currentDialog.close = true
            m.currentDialog.unobserveField("buttonSelected")
        end if
        m.top.getScene().dialog = invalid
        m.currentDialog = invalid
        m.pendingKeyboardClose = false
    end if
    restoreKeyboardFocus(m.pendingKeyboardFocus)
end sub

sub restoreKeyboardFocus(rowIndex as integer)
    if rowIndex < 0 then rowIndex = 0
    if rowIndex > 5 then rowIndex = 5
    setHighlight(rowIndex)
    m.top.setFocus(true)
end sub

sub doLogin()
    host = m.nasAddress
    if host = ""
        showStatus("Please enter your NAS address.", true)
        return
    end if
    if m.username = ""
        showStatus("Please enter your username.", true)
        return
    end if

    port = m.nasPort
    if port = "" then port = "5000"

    if m.useHttps
        baseUrl = "https://" + host + ":" + port
    else
        baseUrl = "http://" + host + ":" + port
    end if
    showStatus("Connecting to " + host + " ...", false)

    task = createObject("roSGNode", "APITask")
    task.request = {
        action: "login",
        baseUrl: baseUrl,
        username: m.username,
        password: m.password
    }
    task.observeField("response", "onLoginResponse")
    task.control = "RUN"
    m.loginTask = task
end sub

sub onLoginResponse(event as object)
    response = event.getData()
    if response = invalid
        showStatus("Network error. Check NAS address and port.", true)
        return
    end if
    if response.success = true
        saveCredentials()
        showStatus("Connected! Loading library...", false)
        m.top.authSuccess = { sid: response.sid, synoToken: response.synoToken, baseUrl: response.baseUrl, username: m.username, password: m.password }
    else
        err = response.error
        if err = invalid then err = "Login failed. Check credentials."
        showStatus(err, true)
    end if
end sub

sub showStatus(msg as string, isError as boolean)
    lbl = m.top.findNode("statusLabel")
    lbl.text = msg
    if isError
        lbl.color = "#FF6B6B"
    else
        lbl.color = "#FFFFFF"
    end if
end sub

sub onKeyInput(event as object)
    key = event.getData()
    if key = invalid or key = "" then return
    handleKey(key)
end sub
