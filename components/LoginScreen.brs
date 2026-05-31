sub init()
      ' Default credentials — overridden by registry if previously saved
      m.nasAddress = ""
      m.nasPort    = "5001"
      m.useHttps   = true
      m.username   = ""
      m.password   = ""
      m.transcodePort = "8099"
      m.activeField = ""
      m.focusIndex = 0
      m.blockFirstOk = false

      m.rowYs = [190, 290, 390, 490, 590, 690, 825]

      m.top.observeField("keyInput", "onKeyInput")
      m.top.observeField("settingsMode", "onSettingsModeChanged")

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
      if reg.exists("nasAddress") then m.nasAddress = reg.read("nasAddress")
      if reg.exists("nasPort") then m.nasPort = reg.read("nasPort")
      if reg.exists("useHttps") then m.useHttps = (reg.read("useHttps") = "true")
      if reg.exists("username") then m.username = reg.read("username")
      if reg.exists("password") then m.password = reg.read("password")
      if reg.exists("transcodePort") then m.transcodePort = reg.read("transcodePort")
      if reg.exists("proxyHost")
          oldProxy = reg.read("proxyHost")
          oldPort = portFromProxyUrl(oldProxy)
          if oldPort <> "" then m.transcodePort = oldPort
      end if
  end sub

sub saveCredentials()
      reg = createObject("roRegistrySection", "DSVideo")
      reg.write("nasAddress", m.nasAddress)
      reg.write("nasPort", m.nasPort)
      if m.useHttps
          reg.write("useHttps", "true")
      else
          reg.write("useHttps", "false")
      end if
      reg.write("username", m.username)
      reg.write("password", m.password)
      reg.write("transcodePort", m.transcodePort)
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
    if m.transcodePort = ""
        m.top.findNode("row5value").text = "8099"
    else
        m.top.findNode("row5value").text = m.transcodePort
    end if
end sub

sub setHighlight(idx as integer)
    m.focusIndex = idx
    yPos = m.rowYs[idx]
    m.top.findNode("rowHighlight").translation = [580, yPos]
    if idx = 6
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
        if m.focusIndex < 6
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
    else if idx = 5
        m.activeField = "transcodePort"
        showKeyboard("Transcode Port", m.transcodePort)
    else if idx = 6 and m.top.settingsMode = true
        saveCredentials()
        showStatus("Settings saved. Press Back to return.", false)
    else if idx = 6
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
    btnIdx = event.getData()
    entered = m.currentDialog.text

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
        else if m.activeField = "transcodePort"
            if entered <> "" then m.transcodePort = entered
            m.top.findNode("row5value").text = m.transcodePort
        end if
    end if

    m.top.getScene().dialog = invalid
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
    proxyBaseUrl = proxyBaseUrlForHost(host, m.transcodePort, m.useHttps)

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
        m.top.authSuccess = { sid: response.sid, synoToken: response.synoToken, baseUrl: response.baseUrl, proxyBaseUrl: proxyBaseUrlForHost(m.nasAddress, m.transcodePort, m.useHttps) }
    else
        err = response.error
        if err = invalid then err = "Login failed. Check credentials."
        showStatus(err, true)
    end if
end sub

function proxyBaseUrlForHost(nasHost as string, transcodePort as string, useHttps as boolean) as string
    port = transcodePort
    if port = "" then port = "8099"
    if useHttps
        return "https://" + nasHost + ":" + port
    end if
    return "http://" + nasHost + ":" + port
end function

function portFromProxyUrl(proxyUrl as string) as string
    if proxyUrl = "" then return ""
    value = proxyUrl
    schemePos = instr(1, value, "://")
    if schemePos > 0 then value = mid(value, schemePos + 3)
    slashPos = instr(1, value, "/")
    if slashPos > 0 then value = left(value, slashPos - 1)
    colonPos = instr(1, value, ":")
    if colonPos > 0 then return mid(value, colonPos + 1)
    return ""
end function

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
