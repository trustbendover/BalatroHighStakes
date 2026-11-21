-- BYTECODE -- heat.lua:12-15
0001    GGET     0   0      ; "MP"
0002    TGETS    0   0   1  ; "LOBBY"
0003    ISF          0
0004    JMP      1 => 0014
0005    GGET     0   0      ; "MP"
0006    TGETS    0   0   1  ; "LOBBY"
0007    TGETS    0   0   2  ; "config"
0008    ISF          0
0009    JMP      1 => 0014
0010    GGET     0   0      ; "MP"
0011    TGETS    0   0   1  ; "LOBBY"
0012    TGETS    0   0   2  ; "config"
0013    TGETS    0   0   3  ; "gamemode"
0014 => GGET     1   4      ; "tostring"
0015    ISTC     3   0
0016    JMP      3 => 0018
0017    KSTR     3   5      ; ""
0018 => CALL     1   2   2
0019    MOV      3   1
0020    TGETS    1   1   6  ; "find"
0021    UGET     4   0      ; H
0022    TGETS    4   4   7  ; "KEY"
0023    KSHORT   5   1
0024    KPRI     6   2
0025    CALL     1   2   5
0026    ISF          1
0027    JMP      2 => 0030
0028    KPRI     1   2
0029    JMP      2 => 0031
0030 => KPRI     1   1
0031 => RET1     1   2

-- BYTECODE -- heat.lua:26-38
0001    GGET     0   0      ; "MP"
0002    TGETS    0   0   1  ; "LOBBY"
0003    ISF          0
0004    JMP      1 => 0012
0005    GGET     0   0      ; "MP"
0006    TGETS    0   0   1  ; "LOBBY"
0007    TGETS    0   0   2  ; "code"
0008    ISEQP    0   0
0009    JMP      0 => 0012
0010    KPRI     0   2
0011    JMP      1 => 0013
0012 => KPRI     0   1
0013 => GGET     1   3      ; "G"
0014    ISF          1
0015    JMP      2 => 0040
0016    GGET     1   3      ; "G"
0017    TGETS    1   1   4  ; "STAGES"
0018    ISF          1
0019    JMP      2 => 0040
0020    GGET     1   3      ; "G"
0021    TGETS    1   1   5  ; "STATES"
0022    ISF          1
0023    JMP      2 => 0040
0024    GGET     1   3      ; "G"
0025    TGETS    1   1   6  ; "STAGE"
0026    GGET     2   3      ; "G"
0027    TGETS    2   2   4  ; "STAGES"
0028    TGETS    2   2   7  ; "RUN"
0029    ISNEV    1   2
0030    JMP      1 => 0040
0031    GGET     1   3      ; "G"
0032    TGETS    1   1   8  ; "STATE"
0033    GGET     2   3      ; "G"
0034    TGETS    2   2   5  ; "STATES"
0035    TGETS    2   2   9  ; "MENU"
0036    ISEQV    1   2
0037    JMP      1 => 0040
0038    KSTR     1  10      ; "run"
0039    JMP      2 => 0041
0040 => KSTR     1  11      ; "menu"
0041 => GGET     2   0      ; "MP"
0042    TGETS    2   2  12  ; "SPECTATE"
0043    ISFC     3   2
0044    JMP      3 => 0054
0045    TGETS    3   2  13  ; "state"
0046    ISF          3
0047    JMP      4 => 0054
0048    TGETS    3   2  13  ; "state"
0049    TGETS    3   3  14  ; "active"
0050    IST          3
0051    JMP      4 => 0054
0052    TGETS    3   2  13  ; "state"
0053    TGETS    3   3  15  ; "joined"
0054 => ISFC     4   0
0055    JMP      4 => 0071
0056    ISTC     4   3
0057    JMP      4 => 0071
0058    ISNES    1  10      ; "run"
0059    JMP      4 => 0068
0060    ISFC     4   2
0061    JMP      4 => 0071
0062    TGETS    4   2  16  ; "watching"
0063    ISF          4
0064    JMP      5 => 0071
0065    TGETS    4   2  16  ; "watching"
0066    CALL     4   2   1
0067    JMP      5 => 0071
0068 => KPRI     4   1
0069    JMP      5 => 0071
0070    KPRI     4   2
0071 => UGET     5   0      ; H
0072    TGETS    5   5  17  ; "music_priority"
0073    TDUP     7  20
0074    GGET     8   0      ; "MP"
0075    TGETS    8   8   1  ; "LOBBY"
0076    ISF          8
0077    JMP      9 => 0087
0078    GGET     8   0      ; "MP"
0079    TGETS    8   8   1  ; "LOBBY"
0080    TGETS    8   8  18  ; "config"
0081    ISF          8
0082    JMP      9 => 0087
0083    GGET     8   0      ; "MP"
0084    TGETS    8   8   1  ; "LOBBY"
0085    TGETS    8   8  18  ; "config"
0086    TGETS    8   8  19  ; "gamemode"
0087 => TSETS    8   7  21  ; "mode"
0088    TSETS    0   7  22  ; "in_lobby"
0089    ISF          4
0090    JMP      8 => 0093
0091    KPRI     8   2
0092    JMP      9 => 0094
0093 => KPRI     8   1
0094 => TSETS    8   7  16  ; "watching"
0095    TSETS    1   7  23  ; "stage"
0096    CALLT    5   2

-- BYTECODE -- heat.lua:17-40
0001    GGET     0   0      ; "SMODS"
0002    ISF          0
0003    JMP      1 => 0019
0004    GGET     0   0      ; "SMODS"
0005    TGETS    0   0   1  ; "Sound"
0006    ISF          0
0007    JMP      1 => 0019
0008    GGET     0   2      ; "NFS"
0009    ISF          0
0010    JMP      1 => 0019
0011    GGET     0   2      ; "NFS"
0012    TGETS    0   0   3  ; "getInfo"
0013    ISF          0
0014    JMP      1 => 0019
0015    GGET     0   4      ; "MP"
0016    TGETS    0   0   5  ; "path"
0017    IST          0
0018    JMP      0 => 0020
0019 => UCLO     0 => 0037
0020 => GGET     0   2      ; "NFS"
0021    TGETS    0   0   3  ; "getInfo"
0022    GGET     2   4      ; "MP"
0023    TGETS    2   2   5  ; "path"
0024    KSTR     3   6      ; "/assets/sounds/music_heat_rush.ogg"
0025    CAT      2   2   3
0026    CALL     0   2   2
0027    IST          0
0028    JMP      0 => 0030
0029    UCLO     0 => 0038
0030 => GGET     0   0      ; "SMODS"
0031    TGETS    0   0   1  ; "Sound"
0032    TDUP     2   7
0033    FNEW     3   8      ; heat.lua:26
0034    TSETS    3   2   9  ; "select_music_track"
0035    CALL     0   1   2
0036    RET0     0   1
0037 => RET0     0   1
0038 => RET0     0   1

-- BYTECODE -- heat.lua:44-46
0001    GGET     0   0      ; "love"
0002    ISF          0
0003    JMP      1 => 0019
0004    GGET     0   0      ; "love"
0005    TGETS    0   0   1  ; "timer"
0006    ISF          0
0007    JMP      1 => 0019
0008    GGET     0   0      ; "love"
0009    TGETS    0   0   1  ; "timer"
0010    TGETS    0   0   2  ; "getTime"
0011    ISF          0
0012    JMP      1 => 0019
0013    GGET     0   0      ; "love"
0014    TGETS    0   0   1  ; "timer"
0015    TGETS    0   0   2  ; "getTime"
0016    CALL     0   2   1
0017    IST          0
0018    JMP      1 => 0022
0019 => GGET     0   3      ; "os"
0020    TGETS    0   0   4  ; "clock"
0021    CALL     0   2   1
0022 => RET1     0   2

-- BYTECODE -- heat.lua:49-51
0001    UGET     0   0      ; H
0002    TGETS    0   0   0  ; "active"
0003    CALL     0   2   1
0004    ISF          0
0005    JMP      1 => 0011
0006    UGET     0   0      ; H
0007    UGET     1   0      ; H
0008    TGETS    1   1   2  ; "now"
0009    CALL     1   2   1
0010    TSETS    1   0   1  ; "started"
0011 => RET0     0   1

-- BYTECODE -- heat.lua:54-70
0001    GGET     1   0      ; "Client"
0002    ISF          1
0003    JMP      2 => 0013
0004    GGET     1   0      ; "Client"
0005    TGETS    1   1   1  ; "send"
0006    ISF          1
0007    JMP      2 => 0013
0008    UGET     1   0      ; H
0009    TGETS    1   1   2  ; "active"
0010    CALL     1   2   1
0011    IST          1
0012    JMP      1 => 0014
0013 => RET0     0   1
0014 => GGET     1   3      ; "G"
0015    ISF          1
0016    JMP      2 => 0026
0017    GGET     1   3      ; "G"
0018    TGETS    1   1   4  ; "GAME"
0019    ISF          1
0020    JMP      2 => 0026
0021    GGET     1   3      ; "G"
0022    TGETS    1   1   4  ; "GAME"
0023    TGETS    1   1   5  ; "current_round"
0024    IST          1
0025    JMP      2 => 0027
0026 => TNEW     1   0
0027 => KSTR     2   6      ; "small"
0028    ISF          0
0029    JMP      3 => 0035
0030    TGETS    3   0   7  ; "boss"
0031    ISF          3
0032    JMP      4 => 0035
0033    KSTR     2   7      ; "boss"
0034    JMP      3 => 0049
0035 => ISF          0
0036    JMP      3 => 0049
0037    TGETS    3   0   8  ; "get_type"
0038    ISF          3
0039    JMP      4 => 0045
0040    MOV      5   0
0041    TGETS    3   0   8  ; "get_type"
0042    CALL     3   2   2
0043    ISEQS    3   9      ; "Big"
0044    JMP      3 => 0048
0045 => TGETS    3   0  10  ; "name"
0046    ISNES    3  11      ; "Big Blind"
0047    JMP      3 => 0049
0048 => KSTR     2  12      ; "big"
0049 => UGET     3   0      ; H
0050    TGETS    3   3  13  ; "now"
0051    CALL     3   2   1
0052    UGET     4   0      ; H
0053    TGETS    4   4  14  ; "PAR_SECONDS"
0054    TGETV    4   4   2
0055    IST          4
0056    JMP      5 => 0058
0057    KSHORT   4  90
0058 => UGET     5   0      ; H
0059    TGETS    5   5  15  ; "started"
0060    ISF          5
0061    JMP      6 => 0067
0062    UGET     5   0      ; H
0063    TGETS    5   5  15  ; "started"
0064    SUBVV    5   3   5
0065    IST          5
0066    JMP      6 => 0068
0067 => ADDVN    5   4   0  ; 1
0068 => UGET     6   0      ; H
0069    KPRI     7   0
0070    TSETS    7   6  15  ; "started"
0071    GGET     6   0      ; "Client"
0072    TGETS    6   6   1  ; "send"
0073    TDUP     8  16
0074    TSETS    2   8  17  ; "blind"
0075    GGET     9  18      ; "tonumber"
0076    TGETS   11   1  19  ; "hands_played"
0077    CALL     9   2   2
0078    IST          9
0079    JMP     10 => 0081
0080    KSHORT   9   1
0081 => TSETS    9   8  20  ; "hands"
0082    TSETS    5   8  21  ; "seconds"
0083    CALL     6   1   2
0084    RET0     0   1

-- BYTECODE -- heat.lua:72-76
0001    GGET     0   0      ; "G"
0002    ISF          0
0003    JMP      1 => 0011
0004    GGET     0   0      ; "G"
0005    TGETS    0   0   1  ; "ROOM"
0006    ISF          0
0007    JMP      1 => 0011
0008    GGET     0   0      ; "G"
0009    TGETS    0   0   1  ; "ROOM"
0010    TGETS    0   0   2  ; "T"
0011 => IST          0
0012    JMP      1 => 0015
0013    KPRI     1   0
0014    RET1     1   2
0015 => TDUP     1   4
0016    TGETS    2   0   3  ; "x"
0017    IST          2
0018    JMP      3 => 0020
0019    KSHORT   2   0
0020 => TSETS    2   1   3  ; "x"
0021    TGETS    2   0   5  ; "y"
0022    IST          2
0023    JMP      3 => 0025
0024    KSHORT   2   0
0025 => TSETS    2   1   5  ; "y"
0026    TGETS    2   0   6  ; "w"
0027    IST          2
0028    JMP      3 => 0030
0029    KSHORT   2   0
0030 => TSETS    2   1   6  ; "w"
0031    TGETS    2   0   7  ; "h"
0032    IST          2
0033    JMP      3 => 0035
0034    KSHORT   2   0
0035 => TSETS    2   1   7  ; "h"
0036    RET1     1   2

-- BYTECODE -- heat.lua:80-85
0001    ISFC     1   0
0002    JMP      1 => 0011
0003    TGETS    1   0   0  ; "REMOVED"
0004    IST          1
0005    JMP      1 => 0008
0006    TGETS    1   0   1  ; "T"
0007    JMP      2 => 0011
0008 => KPRI     1   1
0009    JMP      2 => 0011
0010    KPRI     1   2
0011 => ISF          1
0012    JMP      2 => 0047
0013    TGETS    2   1   2  ; "w"
0014    ISF          2
0015    JMP      3 => 0047
0016    TGETS    2   1   2  ; "w"
0017    KSHORT   3   0
0018    ISGE     3   2
0019    JMP      2 => 0047
0020    TGETS    2   1   3  ; "h"
0021    ISF          2
0022    JMP      3 => 0047
0023    TGETS    2   1   3  ; "h"
0024    KSHORT   3   0
0025    ISGE     3   2
0026    JMP      2 => 0047
0027    UGET     2   0      ; list
0028    UGET     3   0      ; list
0029    LEN      3   3
0030    ADDVN    3   3   0  ; 1
0031    TDUP     4   5
0032    TGETS    5   1   4  ; "x"
0033    IST          5
0034    JMP      6 => 0036
0035    KSHORT   5   0
0036 => TSETS    5   4   4  ; "x"
0037    TGETS    5   1   6  ; "y"
0038    IST          5
0039    JMP      6 => 0041
0040    KSHORT   5   0
0041 => TSETS    5   4   6  ; "y"
0042    TGETS    5   1   2  ; "w"
0043    TSETS    5   4   2  ; "w"
0044    TGETS    5   1   3  ; "h"
0045    TSETS    5   4   3  ; "h"
0046    TSETV    4   2   3
0047 => RET0     0   1

-- BYTECODE -- heat.lua:78-92
0001    TNEW     0   0
0002    FNEW     1   0      ; heat.lua:80
0003    GGET     2   1      ; "MP"
0004    TGETS    2   2   2  ; "GAMBEL"
0005    ISF          2
0006    JMP      3 => 0013
0007    TGETS    3   2   3  ; "badge"
0008    ISF          3
0009    JMP      4 => 0013
0010    MOV      3   1
0011    TGETS    5   2   3  ; "badge"
0012    CALL     3   1   2
0013 => GGET     3   1      ; "MP"
0014    TGETS    3   3   4  ; "CHAT"
0015    ISF          3
0016    JMP      4 => 0023
0017    TGETS    4   3   5  ; "box"
0018    ISF          4
0019    JMP      5 => 0023
0020    MOV      4   1
0021    TGETS    6   3   5  ; "box"
0022    CALL     4   1   2
0023 => GGET     4   6      ; "G"
0024    ISF          4
0025    JMP      5 => 0034
0026    GGET     4   6      ; "G"
0027    TGETS    4   4   7  ; "MP3P_KOTH_UI"
0028    ISF          4
0029    JMP      5 => 0034
0030    MOV      4   1
0031    GGET     6   6      ; "G"
0032    TGETS    6   6   7  ; "MP3P_KOTH_UI"
0033    CALL     4   1   2
0034 => UCLO     0 => 0035
0035 => RET1     0   2

-- BYTECODE -- heat.lua:95-103
0001    IST          0
0002    JMP      1 => 0004
0003    RET0     0   1
0004 => GGET     1   0      ; "G"
0005    ISF          1
0006    JMP      2 => 0014
0007    GGET     1   0      ; "G"
0008    TGETS    1   1   1  ; "ROOM"
0009    ISF          1
0010    JMP      2 => 0014
0011    GGET     1   0      ; "G"
0012    TGETS    1   1   1  ; "ROOM"
0013    TSETS    1   0   2  ; "container"
0014 => TGETS    1   0   3  ; "alignment"
0015    ISF          1
0016    JMP      2 => 0031
0017    TGETS    1   0   3  ; "alignment"
0018    KSTR     2   5      ; "a"
0019    TSETS    2   1   4  ; "type"
0020    TGETS    1   0   3  ; "alignment"
0021    KSTR     2   5      ; "a"
0022    TSETS    2   1   6  ; "prev_type"
0023    TGETS    1   0   3  ; "alignment"
0024    TGETS    1   1   7  ; "type_list"
0025    ISF          1
0026    JMP      2 => 0031
0027    TGETS    1   0   3  ; "alignment"
0028    TGETS    1   1   7  ; "type_list"
0029    KPRI     2   2
0030    TSETS    2   1   5  ; "a"
0031 => RET0     0   1

-- BYTECODE -- heat.lua:108-108
0001    UGET     0   0      ; box
0002    MOV      2   0
0003    TGETS    0   0   0  ; "hard_set_VT"
0004    CALL     0   1   2
0005    RET0     0   1

-- BYTECODE -- heat.lua:117-117
0001    UGET     0   0      ; node
0002    MOV      2   0
0003    TGETS    0   0   0  ; "move_with_major"
0004    KSHORT   3   0
0005    CALL     0   1   3
0006    RET0     0   1

-- BYTECODE -- heat.lua:120-120
0001    UGET     0   0      ; node
0002    MOV      2   0
0003    TGETS    0   0   0  ; "hard_set_VT"
0004    CALL     0   1   2
0005    RET0     0   1

-- BYTECODE -- heat.lua:113-129
0001    GGET     1   0      ; "type"
0002    MOV      3   0
0003    CALL     1   2   2
0004    ISNES    1   1      ; "table"
0005    JMP      1 => 0010
0006    UGET     1   0      ; seen
0007    TGETV    1   1   0
0008    ISF          1
0009    JMP      2 => 0011
0010 => UCLO     0 => 0089
0011 => UGET     1   0      ; seen
0012    KPRI     2   2
0013    TSETV    2   1   0
0014    UGET     1   1      ; box
0015    ISEQV    0   1
0016    JMP      1 => 0030
0017    TGETS    1   0   2  ; "move_with_major"
0018    ISF          1
0019    JMP      2 => 0030
0020    TGETS    1   0   3  ; "role"
0021    ISF          1
0022    JMP      2 => 0030
0023    TGETS    1   0   3  ; "role"
0024    TGETS    1   1   4  ; "major"
0025    ISF          1
0026    JMP      2 => 0030
0027    GGET     1   5      ; "pcall"
0028    FNEW     3   6      ; heat.lua:117
0029    CALL     1   1   2
0030 => TGETS    1   0   7  ; "hard_set_VT"
0031    ISF          1
0032    JMP      2 => 0037
0033    GGET     1   5      ; "pcall"
0034    FNEW     3   8      ; heat.lua:120
0035    CALL     1   1   2
0036    JMP      1 => 0062
0037 => UGET     1   1      ; box
0038    ISEQV    0   1
0039    JMP      1 => 0062
0040    TGETS    1   0   9  ; "VT"
0041    ISF          1
0042    JMP      2 => 0062
0043    TGETS    1   0  10  ; "T"
0044    ISF          1
0045    JMP      2 => 0062
0046    TGETS    1   0   9  ; "VT"
0047    TGETS    2   0   9  ; "VT"
0048    TGETS    3   0   9  ; "VT"
0049    TGETS    4   0   9  ; "VT"
0050    TGETS    5   0  10  ; "T"
0051    TGETS    5   5  11  ; "x"
0052    TGETS    6   0  10  ; "T"
0053    TGETS    6   6  12  ; "y"
0054    TGETS    7   0  10  ; "T"
0055    TGETS    7   7  13  ; "w"
0056    TGETS    8   0  10  ; "T"
0057    TGETS    8   8  14  ; "h"
0058    TSETS    8   4  14  ; "h"
0059    TSETS    7   3  13  ; "w"
0060    TSETS    6   2  12  ; "y"
0061    TSETS    5   1  11  ; "x"
0062 => TGETS    1   0  15  ; "config"
0063    ISF          1
0064    JMP      2 => 0067
0065    TGETS    1   0  15  ; "config"
0066    TGETS    1   1  16  ; "object"
0067 => GGET     2   0      ; "type"
0068    MOV      4   1
0069    CALL     2   2   2
0070    ISNES    2   1      ; "table"
0071    JMP      2 => 0075
0072    UGET     2   2      ; snap
0073    MOV      4   1
0074    CALL     2   1   2
0075 => TGETS    2   0  17  ; "children"
0076    ISF          2
0077    JMP      3 => 0087
0078    GGET     2  18      ; "ipairs"
0079    TGETS    4   0  17  ; "children"
0080    CALL     2   4   2
0081    JMP      5 => 0085
0082 => UGET     7   2      ; snap
0083    MOV      9   6
0084    CALL     7   1   2
0085 => ITERC    5   3   3
0086    ITERL    5 => 0082
0087 => UCLO     0 => 0088
0088 => RET0     0   1
0089 => RET0     0   1

-- BYTECODE -- heat.lua:105-132
0001    ISF          0
0002    JMP      1 => 0006
0003    TGETS    1   0   0  ; "T"
0004    IST          1
0005    JMP      1 => 0007
0006 => UCLO     0 => 0046
0007 => TGETS    1   0   1  ; "hard_set_VT"
0008    ISF          1
0009    JMP      2 => 0014
0010    GGET     1   2      ; "pcall"
0011    FNEW     3   3      ; heat.lua:108
0012    CALL     1   1   2
0013    JMP      1 => 0033
0014 => TGETS    1   0   4  ; "VT"
0015    ISF          1
0016    JMP      2 => 0033
0017    TGETS    1   0   4  ; "VT"
0018    TGETS    2   0   4  ; "VT"
0019    TGETS    3   0   4  ; "VT"
0020    TGETS    4   0   4  ; "VT"
0021    TGETS    5   0   0  ; "T"
0022    TGETS    5   5   5  ; "x"
0023    TGETS    6   0   0  ; "T"
0024    TGETS    6   6   6  ; "y"
0025    TGETS    7   0   0  ; "T"
0026    TGETS    7   7   7  ; "w"
0027    TGETS    8   0   0  ; "T"
0028    TGETS    8   8   8  ; "h"
0029    TSETS    8   4   8  ; "h"
0030    TSETS    7   3   7  ; "w"
0031    TSETS    6   2   6  ; "y"
0032    TSETS    5   1   5  ; "x"
0033 => TNEW     1   0
0034    FNEW     2   9      ; heat.lua:113
0035    MOV      3   2
0036    MOV      5   0
0037    CALL     3   1   2
0038    TGETS    3   0  10  ; "UIRoot"
0039    ISF          3
0040    JMP      4 => 0044
0041    MOV      3   2
0042    TGETS    5   0  10  ; "UIRoot"
0043    CALL     3   1   2
0044 => UCLO     0 => 0045
0045 => RET0     0   1
0046 => RET0     0   1

-- BYTECODE -- heat.lua:134-146
0001    UGET     0   0      ; H
0002    TGETS    0   0   0  ; "badge"
0003    GGET     1   1      ; "G"
0004    ISF          1
0005    JMP      2 => 0008
0006    GGET     1   1      ; "G"
0007    TGETS    1   1   2  ; "jokers"
0008 => ISF          0
0009    JMP      2 => 0015
0010    TGETS    2   0   3  ; "REMOVED"
0011    IST          2
0012    JMP      3 => 0015
0013    IST          1
0014    JMP      2 => 0016
0015 => RET0     0   1
0016 => UGET     2   0      ; H
0017    TGETS    2   2   4  ; "layout_badge"
0018    MOV      4   1
0019    TGETS    5   1   5  ; "cards"
0020    UGET     6   0      ; H
0021    TGETS    6   6   6  ; "blockers"
0022    CALL     6   2   1
0023    UGET     7   0      ; H
0024    TGETS    7   7   7  ; "room_rect"
0025    CALL     7   0   1
0026    CALLM    2   2   3
0027    IST          2
0028    JMP      3 => 0030
0029    RET0     0   1
0030 => UGET     3   0      ; H
0031    TGETS    3   3   8  ; "hold"
0032    MOV      5   0
0033    CALL     3   1   2
0034    TGETS    3   0   9  ; "T"
0035    TGETS    4   0   9  ; "T"
0036    TGETS    5   0   9  ; "T"
0037    TGETS    6   0   9  ; "T"
0038    TGETS    7   2  10  ; "x"
0039    TGETS    8   2  11  ; "y"
0040    TGETS    9   2  12  ; "w"
0041    TGETS   10   2  13  ; "h"
0042    TSETS   10   6  13  ; "h"
0043    TSETS    9   5  12  ; "w"
0044    TSETS    8   4  11  ; "y"
0045    TSETS    7   3  10  ; "x"
0046    TGETS    3   0  14  ; "VT"
0047    ISF          3
0048    JMP      4 => 0061
0049    TGETS    3   0  14  ; "VT"
0050    TGETS    4   0  14  ; "VT"
0051    TGETS    5   0  14  ; "VT"
0052    TGETS    6   0  14  ; "VT"
0053    TGETS    7   2  10  ; "x"
0054    TGETS    8   2  11  ; "y"
0055    TGETS    9   2  12  ; "w"
0056    TGETS   10   2  13  ; "h"
0057    TSETS   10   6  13  ; "h"
0058    TSETS    9   5  12  ; "w"
0059    TSETS    8   4  11  ; "y"
0060    TSETS    7   3  10  ; "x"
0061 => TGETS    3   0  15  ; "velocity"
0062    ISF          3
0063    JMP      4 => 0070
0064    TGETS    3   0  15  ; "velocity"
0065    TGETS    4   0  15  ; "velocity"
0066    KSHORT   5   0
0067    KSHORT   6   0
0068    TSETS    6   4  11  ; "y"
0069    TSETS    5   3  10  ; "x"
0070 => UGET     3   0      ; H
0071    TGETS    3   3  16  ; "sync_visual"
0072    MOV      5   0
0073    CALL     3   1   2
0074    UGET     3   0      ; H
0075    TSETS    2   3  17  ; "slot"
0076    RET0     0   1

-- BYTECODE -- heat.lua:153-156
0001    UGET     1   0      ; H
0002    TGETS    1   1   0  ; "_painting"
0003    IST          1
0004    JMP      1 => 0006
0005    RET0     0   1
0006 => UGET     1   1      ; orig
0007    MOV      3   0
0008    VARG     4   0   1
0009    CALLMT   1   1

-- BYTECODE -- heat.lua:149-157
0001    ISF          0
0002    JMP      1 => 0009
0003    TGETS    1   0   0  ; "_mp_heat_draw"
0004    IST          1
0005    JMP      2 => 0009
0006    TGETS    1   0   1  ; "draw"
0007    IST          1
0008    JMP      1 => 0010
0009 => UCLO     0 => 0016
0010 => TGETS    1   0   1  ; "draw"
0011    TSETS    1   0   0  ; "_mp_heat_draw"
0012    FNEW     2   2      ; heat.lua:153
0013    TSETS    2   0   1  ; "draw"
0014    UCLO     0 => 0015
0015 => RET0     0   1
0016 => RET0     0   1

-- BYTECODE -- heat.lua:168-171
0001    UGET     0   0      ; box
0002    TGETS    0   0   0  ; "translate_container"
0003    ISF          0
0004    JMP      1 => 0009
0005    UGET     0   0      ; box
0006    MOV      2   0
0007    TGETS    0   0   0  ; "translate_container"
0008    CALL     0   1   2
0009 => UGET     0   0      ; box
0010    MOV      2   0
0011    TGETS    0   0   1  ; "draw"
0012    CALL     0   1   2
0013    RET0     0   1

-- BYTECODE -- heat.lua:166-174
0001    GGET     0   0      ; "love"
0002    TGETS    0   0   1  ; "graphics"
0003    TGETS    0   0   2  ; "push"
0004    CALL     0   1   1
0005    GGET     0   3      ; "pcall"
0006    FNEW     2   4      ; heat.lua:168
0007    CALL     0   3   2
0008    GGET     2   0      ; "love"
0009    TGETS    2   2   1  ; "graphics"
0010    TGETS    2   2   5  ; "pop"
0011    CALL     2   1   1
0012    IST          0
0013    JMP      2 => 0017
0014    GGET     2   6      ; "error"
0015    MOV      4   1
0016    CALL     2   1   2
0017 => RET0     0   1

-- BYTECODE -- heat.lua:159-176
0001    UGET     0   0      ; H
0002    TGETS    0   0   0  ; "badge"
0003    ISF          0
0004    JMP      1 => 0011
0005    TGETS    1   0   1  ; "REMOVED"
0006    IST          1
0007    JMP      2 => 0011
0008    TGETS    1   0   2  ; "draw"
0009    IST          1
0010    JMP      1 => 0012
0011 => UCLO     0 => 0040
0012 => GGET     1   3      ; "G"
0013    ISF          1
0014    JMP      2 => 0020
0015    GGET     1   3      ; "G"
0016    TGETS    1   1   4  ; "OVERLAY_MENU"
0017    ISF          1
0018    JMP      2 => 0020
0019    UCLO     0 => 0041
0020 => UGET     1   0      ; H
0021    TGETS    1   1   5  ; "pin"
0022    CALL     1   1   1
0023    TGETS    1   0   6  ; "FRAME"
0024    ISF          1
0025    JMP      2 => 0029
0026    TGETS    1   0   6  ; "FRAME"
0027    KSHORT   2  -1
0028    TSETS    2   1   7  ; "DRAW"
0029 => UGET     1   0      ; H
0030    KPRI     2   2
0031    TSETS    2   1   8  ; "_painting"
0032    GGET     1   9      ; "pcall"
0033    FNEW     3  10      ; heat.lua:166
0034    CALL     1   1   2
0035    UGET     1   0      ; H
0036    KPRI     2   1
0037    TSETS    2   1   8  ; "_painting"
0038    UCLO     0 => 0039
0039 => RET0     0   1
0040 => RET0     0   1
0041 => RET0     0   1

-- BYTECODE -- heat.lua:182-182
0001    UGET     0   0      ; H
0002    TGETS    0   0   0  ; "badge"
0003    MOV      2   0
0004    TGETS    0   0   1  ; "remove"
0005    CALL     0   1   2
0006    RET0     0   1

-- BYTECODE -- heat.lua:178-209
0001    GGET     0   0      ; "G"
0002    ISF          0
0003    JMP      1 => 0019
0004    GGET     0   1      ; "UIBox"
0005    ISF          0
0006    JMP      1 => 0019
0007    GGET     0   0      ; "G"
0008    TGETS    0   0   2  ; "UIT"
0009    ISF          0
0010    JMP      1 => 0019
0011    GGET     0   0      ; "G"
0012    TGETS    0   0   3  ; "ROOM_ATTACH"
0013    ISF          0
0014    JMP      1 => 0019
0015    GGET     0   0      ; "G"
0016    TGETS    0   0   4  ; "STAGES"
0017    IST          0
0018    JMP      0 => 0020
0019 => UCLO     0 => 0269
0020 => UGET     0   0      ; H
0021    TGETS    0   0   5  ; "active"
0022    CALL     0   2   1
0023    ISF          0
0024    JMP      1 => 0043
0025    GGET     0   0      ; "G"
0026    TGETS    0   0   6  ; "STAGE"
0027    GGET     1   0      ; "G"
0028    TGETS    1   1   4  ; "STAGES"
0029    TGETS    1   1   7  ; "RUN"
0030    ISNEV    0   1
0031    JMP      0 => 0040
0032    GGET     0   0      ; "G"
0033    TGETS    0   0   8  ; "jokers"
0034    ISF          0
0035    JMP      1 => 0043
0036    GGET     0   0      ; "G"
0037    TGETS    0   0   8  ; "jokers"
0038    TGETS    0   0   9  ; "T"
0039    JMP      1 => 0043
0040 => KPRI     0   1
0041    JMP      1 => 0043
0042    KPRI     0   2
0043 => IST          0
0044    JMP      1 => 0064
0045    UGET     1   0      ; H
0046    TGETS    1   1  10  ; "badge"
0047    ISF          1
0048    JMP      2 => 0057
0049    UGET     1   0      ; H
0050    TGETS    1   1  10  ; "badge"
0051    TGETS    1   1  11  ; "remove"
0052    ISF          1
0053    JMP      2 => 0057
0054    GGET     1  12      ; "pcall"
0055    FNEW     3  13      ; heat.lua:182
0056    CALL     1   1   2
0057 => UGET     1   0      ; H
0058    UGET     2   0      ; H
0059    KNIL     3   4
0060    TSETS    4   2  14  ; "slot"
0061    TSETS    3   1  10  ; "badge"
0062    UCLO     0 => 0063
0063 => RET0     0   1
0064 => GGET     1  15      ; "MP"
0065    TGETS    1   1  16  ; "GAME"
0066    IST          1
0067    JMP      2 => 0069
0068    TNEW     1   0
0069 => GGET     2  17      ; "love"
0070    ISF          2
0071    JMP      3 => 0087
0072    GGET     2  17      ; "love"
0073    TGETS    2   2  18  ; "timer"
0074    ISF          2
0075    JMP      3 => 0087
0076    GGET     2  17      ; "love"
0077    TGETS    2   2  18  ; "timer"
0078    TGETS    2   2  19  ; "getTime"
0079    ISF          2
0080    JMP      3 => 0087
0081    GGET     2  17      ; "love"
0082    TGETS    2   2  18  ; "timer"
0083    TGETS    2   2  19  ; "getTime"
0084    CALL     2   2   1
0085    IST          2
0086    JMP      3 => 0090
0087 => GGET     2  20      ; "os"
0088    TGETS    2   2  21  ; "clock"
0089    CALL     2   2   1
0090 => UGET     3   0      ; H
0091    TGETS    3   3  22  ; "started"
0092    IST          3
0093    JMP      3 => 0096
0094    UGET     3   0      ; H
0095    TSETS    2   3  22  ; "started"
0096 => GGET     3  23      ; "string"
0097    TGETS    3   3  24  ; "format"
0098    KSTR     5  25      ; "HEAT %d/%d"
0099    GGET     6  26      ; "tonumber"
0100    TGETS    8   1  27  ; "heat"
0101    CALL     6   2   2
0102    IST          6
0103    JMP      7 => 0105
0104    KSHORT   6   0
0105 => UGET     7   0      ; H
0106    TGETS    7   7  28  ; "MAX"
0107    CALL     3   2   4
0108    GGET     4   0      ; "G"
0109    ISF          4
0110    JMP      5 => 0118
0111    GGET     4   0      ; "G"
0112    TGETS    4   4  16  ; "GAME"
0113    ISF          4
0114    JMP      5 => 0118
0115    GGET     4   0      ; "G"
0116    TGETS    4   4  16  ; "GAME"
0117    TGETS    4   4  29  ; "blind"
0118 => ISF          4
0119    JMP      5 => 0147
0120    TGETS    5   4  30  ; "boss"
0121    ISF          5
0122    JMP      6 => 0147
0123    UGET     5   0      ; H
0124    TGETS    5   5  22  ; "started"
0125    ISF          5
0126    JMP      6 => 0147
0127    MOV      5   3
0128    GGET     6  23      ; "string"
0129    TGETS    6   6  24  ; "format"
0130    KSTR     8  31      ; "  BOSS %ds"
0131    GGET     9  32      ; "math"
0132    TGETS    9   9  33  ; "max"
0133    KSHORT  11   0
0134    GGET    12  32      ; "math"
0135    TGETS   12  12  34  ; "floor"
0136    UGET    14   0      ; H
0137    TGETS   14  14  35  ; "PAR_SECONDS"
0138    TGETS   14  14  30  ; "boss"
0139    UGET    15   0      ; H
0140    TGETS   15  15  22  ; "started"
0141    SUBVV   15   2  15
0142    SUBVV   14  14  15
0143    CALL    12   0   2
0144    CALLM    9   0   1
0145    CALLM    6   2   1
0146    CAT      3   5   6
0147 => TGETS    5   1  36  ; "heat_overdrive"
0148    ISF          5
0149    JMP      6 => 0153
0150    MOV      5   3
0151    KSTR     6  37      ; "  OVERDRIVE"
0152    CAT      3   5   6
0153 => GGET     5  26      ; "tonumber"
0154    TGETS    7   1  38  ; "heat_best"
0155    CALL     5   2   2
0156    IST          5
0157    JMP      6 => 0159
0158    KSHORT   5   0
0159 => KSHORT   6   0
0160    ISGE     6   5
0161    JMP      5 => 0169
0162    MOV      5   3
0163    GGET     6  23      ; "string"
0164    TGETS    6   6  24  ; "format"
0165    KSTR     8  39      ; "  Best %d"
0166    TGETS    9   1  38  ; "heat_best"
0167    CALL     6   2   3
0168    CAT      3   5   6
0169 => UGET     5   0      ; H
0170    TGETS    5   5  40  ; "view"
0171    TSETS    3   5  41  ; "text"
0172    UGET     5   0      ; H
0173    TGETS    5   5  10  ; "badge"
0174    ISF          5
0175    JMP      5 => 0181
0176    UGET     5   0      ; H
0177    TGETS    5   5  10  ; "badge"
0178    TGETS    5   5  42  ; "REMOVED"
0179    ISF          5
0180    JMP      6 => 0265
0181 => UGET     5   0      ; H
0182    GGET     6   1      ; "UIBox"
0183    TDUP     8  65
0184    TDUP     9  44
0185    GGET    10   0      ; "G"
0186    TGETS   10  10   2  ; "UIT"
0187    TGETS   10  10  43  ; "ROOT"
0188    TSETS   10   9  45  ; "n"
0189    TDUP    10  46
0190    GGET    11   0      ; "G"
0191    TGETS   11  11  47  ; "C"
0192    TGETS   11  11  48  ; "CLEAR"
0193    TSETS   11  10  49  ; "colour"
0194    UGET    11   0      ; H
0195    TGETS   11  11  50  ; "BADGE_W"
0196    TSETS   11  10  51  ; "minw"
0197    UGET    11   0      ; H
0198    TGETS   11  11  52  ; "BADGE_H"
0199    TSETS   11  10  53  ; "minh"
0200    TSETS   10   9  54  ; "config"
0201    TNEW    10   3
0202    TDUP    11  56
0203    GGET    12   0      ; "G"
0204    TGETS   12  12   2  ; "UIT"
0205    TGETS   12  12  55  ; "R"
0206    TSETS   12  11  45  ; "n"
0207    TDUP    12  57
0208    GGET    13   0      ; "G"
0209    TGETS   13  13  47  ; "C"
0210    TGETS   13  13  58  ; "BLACK"
0211    TSETS   13  12  49  ; "colour"
0212    UGET    13   0      ; H
0213    TGETS   13  13  50  ; "BADGE_W"
0214    TSETS   13  12  51  ; "minw"
0215    TSETS   12  11  54  ; "config"
0216    TNEW    12   3
0217    TDUP    13  59
0218    GGET    14   0      ; "G"
0219    TGETS   14  14   2  ; "UIT"
0220    TGETS   14  14   9  ; "T"
0221    TSETS   14  13  45  ; "n"
0222    TDUP    14  60
0223    UGET    15   0      ; H
0224    TGETS   15  15  40  ; "view"
0225    TSETS   15  14  61  ; "ref_table"
0226    GGET    15   0      ; "G"
0227    TGETS   15  15  47  ; "C"
0228    TGETS   15  15  62  ; "GOLD"
0229    IST         15
0230    JMP     16 => 0234
0231    GGET    15   0      ; "G"
0232    TGETS   15  15  47  ; "C"
0233    TGETS   15  15  63  ; "WHITE"
0234 => TSETS   15  14  49  ; "colour"
0235    TSETS   14  13  54  ; "config"
0236    TSETB   13  12   1
0237    TSETS   12  11  64  ; "nodes"
0238    TSETB   11  10   1
0239    TSETS   10   9  64  ; "nodes"
0240    TSETS    9   8  66  ; "definition"
0241    TDUP     9  67
0242    TDUP    10  68
0243    UGET    11   0      ; H
0244    TGETS   11  11  52  ; "BADGE_H"
0245    UGET    12   0      ; H
0246    TGETS   12  12  69  ; "BADGE_GAP"
0247    ADDVV   11  11  12
0248    UGET    12   0      ; H
0249    TGETS   12  12  70  ; "HOVER"
0250    ADDVV   11  11  12
0251    UNM     11  11
0252    TSETS   11  10  71  ; "y"
0253    TSETS   10   9  72  ; "offset"
0254    GGET    10   0      ; "G"
0255    TGETS   10  10   8  ; "jokers"
0256    TSETS   10   9  73  ; "major"
0257    TSETS    9   8  54  ; "config"
0258    CALL     6   2   2
0259    TSETS    6   5  10  ; "badge"
0260    UGET     5   0      ; H
0261    TGETS    5   5  74  ; "silence"
0262    UGET     7   0      ; H
0263    TGETS    7   7  10  ; "badge"
0264    CALL     5   1   2
0265 => UGET     5   0      ; H
0266    TGETS    5   5  75  ; "pin"
0267    CALL     5   1   1
0268    RET0     0   1
0269 => RET0     0   1

-- BYTECODE -- heat.lua:225-225
0001    GGET     0   0      ; "add_tag"
0002    GGET     2   1      ; "Tag"
0003    UGET     4   0      ; p
0004    TGETS    4   4   2  ; "tag"
0005    CALL     2   0   2
0006    CALLM    0   1   0
0007    RET0     0   1

-- BYTECODE -- heat.lua:211-228
0001    GGET     1   0      ; "type"
0002    MOV      3   0
0003    CALL     1   2   2
0004    ISEQS    1   1      ; "table"
0005    JMP      1 => 0007
0006    UCLO     0 => 0137
0007 => GGET     1   2      ; "MP"
0008    GGET     2   2      ; "MP"
0009    TGETS    2   2   3  ; "GAME"
0010    IST          2
0011    JMP      3 => 0013
0012    TNEW     2   0
0013 => TSETS    2   1   3  ; "GAME"
0014    GGET     1   2      ; "MP"
0015    TGETS    1   1   3  ; "GAME"
0016    GGET     2   5      ; "tonumber"
0017    TGETS    4   0   4  ; "heat"
0018    CALL     2   2   2
0019    IST          2
0020    JMP      3 => 0022
0021    KSHORT   2   0
0022 => TSETS    2   1   4  ; "heat"
0023    GGET     1   2      ; "MP"
0024    TGETS    1   1   3  ; "GAME"
0025    GGET     2   5      ; "tonumber"
0026    TGETS    4   0   7  ; "total"
0027    CALL     2   2   2
0028    IST          2
0029    JMP      3 => 0036
0030    GGET     2   2      ; "MP"
0031    TGETS    2   2   3  ; "GAME"
0032    TGETS    2   2   6  ; "heat_total"
0033    IST          2
0034    JMP      3 => 0036
0035    KSHORT   2   0
0036 => TSETS    2   1   6  ; "heat_total"
0037    GGET     1   2      ; "MP"
0038    TGETS    1   1   3  ; "GAME"
0039    GGET     2   5      ; "tonumber"
0040    TGETS    4   0   9  ; "best"
0041    CALL     2   2   2
0042    IST          2
0043    JMP      3 => 0050
0044    GGET     2   2      ; "MP"
0045    TGETS    2   2   3  ; "GAME"
0046    TGETS    2   2   8  ; "heat_best"
0047    IST          2
0048    JMP      3 => 0050
0049    KSHORT   2   0
0050 => TSETS    2   1   8  ; "heat_best"
0051    GGET     1   2      ; "MP"
0052    TGETS    1   1   3  ; "GAME"
0053    TGETS    2   0  11  ; "overdrive"
0054    ISF          2
0055    JMP      3 => 0058
0056    KPRI     2   2
0057    JMP      3 => 0059
0058 => KPRI     2   1
0059 => TSETS    2   1  10  ; "heat_overdrive"
0060    GGET     1   2      ; "MP"
0061    TGETS    1   1   3  ; "GAME"
0062    TGETS    2   0  13  ; "rows"
0063    TSETS    2   1  12  ; "heat_board"
0064    TGETS    1   0  14  ; "reward"
0065    ISNES    1  15      ; "cash"
0066    JMP      1 => 0086
0067    GGET     1  16      ; "ease_dollars"
0068    ISF          1
0069    JMP      2 => 0086
0070    GGET     1  17      ; "G"
0071    ISF          1
0072    JMP      2 => 0086
0073    GGET     1  17      ; "G"
0074    TGETS    1   1  18  ; "STAGE"
0075    GGET     2  17      ; "G"
0076    TGETS    2   2  19  ; "STAGES"
0077    TGETS    2   2  20  ; "RUN"
0078    ISNEV    1   2
0079    JMP      1 => 0086
0080    GGET     1  21      ; "pcall"
0081    GGET     3  16      ; "ease_dollars"
0082    UGET     4   0      ; H
0083    TGETS    4   4  22  ; "CASH"
0084    CALL     1   1   3
0085    JMP      1 => 0106
0086 => TGETS    1   0  14  ; "reward"
0087    ISNES    1  23      ; "reroll"
0088    JMP      1 => 0106
0089    GGET     1  17      ; "G"
0090    ISF          1
0091    JMP      2 => 0106
0092    GGET     1  17      ; "G"
0093    TGETS    1   1   3  ; "GAME"
0094    ISF          1
0095    JMP      2 => 0106
0096    GGET     1  17      ; "G"
0097    TGETS    1   1   3  ; "GAME"
0098    TGETS    1   1  24  ; "current_round"
0099    ISF          1
0100    JMP      2 => 0106
0101    GGET     1  17      ; "G"
0102    TGETS    1   1   3  ; "GAME"
0103    TGETS    1   1  24  ; "current_round"
0104    KSHORT   2   0
0105    TSETS    2   1  25  ; "reroll_cost"
0106 => TGETS    1   0  26  ; "tag"
0107    ISF          1
0108    JMP      2 => 0128
0109    GGET     1  27      ; "add_tag"
0110    ISF          1
0111    JMP      2 => 0128
0112    GGET     1  28      ; "Tag"
0113    ISF          1
0114    JMP      2 => 0128
0115    GGET     1  17      ; "G"
0116    ISF          1
0117    JMP      2 => 0128
0118    GGET     1  17      ; "G"
0119    TGETS    1   1  18  ; "STAGE"
0120    GGET     2  17      ; "G"
0121    TGETS    2   2  19  ; "STAGES"
0122    TGETS    2   2  20  ; "RUN"
0123    ISNEV    1   2
0124    JMP      1 => 0128
0125    GGET     1  21      ; "pcall"
0126    FNEW     3  29      ; heat.lua:225
0127    CALL     1   1   2
0128 => UGET     1   0      ; H
0129    TGETS    1   1  30  ; "sync_badge"
0130    ISF          1
0131    JMP      2 => 0135
0132    UGET     1   0      ; H
0133    TGETS    1   1  30  ; "sync_badge"
0134    CALL     1   1   1
0135 => UCLO     0 => 0136
0136 => RET0     0   1
0137 => RET0     0   1

-- BYTECODE -- heat.lua:233-237
0001    UGET     0   0      ; draw
0002    VARG     2   0   0
0003    CALLM    0   2   0
0004    UGET     1   1      ; H
0005    TGETS    1   1   0  ; "draw_front"
0006    ISF          1
0007    JMP      2 => 0011
0008    UGET     1   1      ; H
0009    TGETS    1   1   0  ; "draw_front"
0010    CALL     1   1   1
0011 => RET1     0   2

-- BYTECODE -- heat.lua:243-247
0001    UGET     2   0      ; upd
0002    MOV      4   0
0003    MOV      5   1
0004    CALL     2   2   3
0005    UGET     3   1      ; H
0006    TGETS    3   3   0  ; "active"
0007    ISF          3
0008    JMP      4 => 0021
0009    UGET     3   1      ; H
0010    TGETS    3   3   0  ; "active"
0011    CALL     3   2   1
0012    ISF          3
0013    JMP      4 => 0021
0014    UGET     3   1      ; H
0015    TGETS    3   3   1  ; "sync_badge"
0016    ISF          3
0017    JMP      4 => 0021
0018    UGET     3   1      ; H
0019    TGETS    3   3   1  ; "sync_badge"
0020    CALL     3   1   1
0021 => RET1     2   2

-- BYTECODE -- heat.lua:0-249
0001    GGET     0   0      ; "MP"
0002    TGETS    0   0   1  ; "load_mp_file"
0003    ISF          0
0004    JMP      1 => 0011
0005    GGET     0   0      ; "MP"
0006    TGETS    0   0   1  ; "load_mp_file"
0007    KSTR     2   2      ; "networking/heat_rules.lua"
0008    CALL     0   2   2
0009    IST          0
0010    JMP      1 => 0012
0011 => KPRI     0   0
0012 => IST          0
0013    JMP      1 => 0021
0014    GGET     1   3      ; "pcall"
0015    GGET     3   4      ; "dofile"
0016    KSTR     4   2      ; "networking/heat_rules.lua"
0017    CALL     1   3   3
0018    ISF          1
0019    JMP      3 => 0021
0020    MOV      0   2
0021 => IST          0
0022    JMP      1 => 0024
0023    UCLO     0 => 0099
0024 => GGET     1   0      ; "MP"
0025    TSETS    0   1   5  ; "HEAT"
0026    TGETS    1   0   6  ; "view"
0027    IST          1
0028    JMP      2 => 0030
0029    TDUP     1   7
0030 => TSETS    1   0   6  ; "view"
0031    FNEW     1   9      ; heat.lua:12
0032    TSETS    1   0   8  ; "active"
0033    FNEW     1  11      ; heat.lua:17
0034    TSETS    1   0  10  ; "register_music"
0035    TGETS    1   0  10  ; "register_music"
0036    CALL     1   1   1
0037    FNEW     1  13      ; heat.lua:44
0038    TSETS    1   0  12  ; "now"
0039    FNEW     1  15      ; heat.lua:49
0040    TSETS    1   0  14  ; "arm"
0041    FNEW     1  17      ; heat.lua:54
0042    TSETS    1   0  16  ; "report"
0043    FNEW     1  19      ; heat.lua:72
0044    TSETS    1   0  18  ; "room_rect"
0045    FNEW     1  21      ; heat.lua:78
0046    TSETS    1   0  20  ; "blockers"
0047    FNEW     1  23      ; heat.lua:95
0048    TSETS    1   0  22  ; "hold"
0049    FNEW     1  25      ; heat.lua:105
0050    TSETS    1   0  24  ; "sync_visual"
0051    FNEW     1  27      ; heat.lua:134
0052    TSETS    1   0  26  ; "pin"
0053    FNEW     1  29      ; heat.lua:149
0054    TSETS    1   0  28  ; "silence"
0055    FNEW     1  31      ; heat.lua:159
0056    TSETS    1   0  30  ; "draw_front"
0057    FNEW     1  33      ; heat.lua:178
0058    TSETS    1   0  32  ; "sync_badge"
0059    FNEW     1  35      ; heat.lua:211
0060    TSETS    1   0  34  ; "on_state"
0061    GGET     1  36      ; "love"
0062    ISF          1
0063    JMP      2 => 0079
0064    GGET     1  36      ; "love"
0065    TGETS    1   1  37  ; "draw"
0066    ISF          1
0067    JMP      2 => 0079
0068    TGETS    1   0  38  ; "_draw"
0069    IST          1
0070    JMP      1 => 0079
0071    KPRI     1   2
0072    TSETS    1   0  38  ; "_draw"
0073    GGET     1  36      ; "love"
0074    TGETS    1   1  37  ; "draw"
0075    GGET     2  36      ; "love"
0076    FNEW     3  39      ; heat.lua:233
0077    TSETS    3   2  37  ; "draw"
0078    UCLO     1 => 0079
0079 => GGET     1  40      ; "Game"
0080    ISF          1
0081    JMP      2 => 0097
0082    GGET     1  40      ; "Game"
0083    TGETS    1   1  41  ; "update"
0084    ISF          1
0085    JMP      2 => 0097
0086    TGETS    1   0  42  ; "_ui"
0087    IST          1
0088    JMP      1 => 0097
0089    KPRI     1   2
0090    TSETS    1   0  42  ; "_ui"
0091    GGET     1  40      ; "Game"
0092    TGETS    1   1  41  ; "update"
0093    GGET     2  40      ; "Game"
0094    FNEW     3  43      ; heat.lua:243
0095    TSETS    3   2  41  ; "update"
0096    UCLO     1 => 0097
0097 => UCLO     0 => 0098
0098 => RET0     0   1
0099 => RET0     0   1

