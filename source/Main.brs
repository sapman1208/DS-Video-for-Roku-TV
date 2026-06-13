sub Main()
    print "MAIN_START version=1.8.12-summary-refresh-guard"
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    screen.CreateScene("MainScene")
    screen.show()

    while true
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent"
            if msg.isScreenClosed()
                return
            end if
        end if
    end while
end sub
