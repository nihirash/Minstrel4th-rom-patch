    LUA ALLPASS
        link = 7512
    ENDLUA


    MACRO FORTH_WORD wordname
.name
    ABYTEC 0 wordname
.name_end
    LUA ALLPASS
        _pc("dw " .. link)
        link = _c("$")
    ENDLUA
    db .name_end - .name
    dw $ + 2
    ENDM