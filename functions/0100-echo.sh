_COLOR_BLACK='\033[0;30m'
_COLOR_DARKGRAY='\033[1;30m'
_COLOR_RED='\033[0;31m'
_COLOR_LIGHTRED='\033[1;31m'
_COLOR_GREEN='\033[0;32m'
_COLOR_LIGHTGREEN='\033[1;32m'
_COLOR_ORANGE='\033[0;33m'
_COLOR_YELLOW='\033[1;33m'
_COLOR_BLUE='\033[0;34m'
_COLOR_LIGHTBLUE='\033[1;34m'
_COLOR_PURPLE='\033[0;35m'
_COLOR_LIGHTPURPLE='\033[1;35m'
_COLOR_CYAN='\033[0;36m'
_COLOR_LIGHTCYAN='\033[1;36m'
_COLOR_LIGHTGRAY='\033[0;37m'
_COLOR_WHITE='\033[1;37m'
_COLOR_NORMAL='\033[0m' # No Color

echo_error(){
    if [ $_LOG_LEVEL -gt 0 ] && [ $_LOG_LEVEL -lt 4  ]; then
        echo -e "${_COLOR_RED}$@${_COLOR_NORMAL}"
    fi
}

echo_warn(){
    if [ $_LOG_LEVEL -gt 0 ] && [ $_LOG_LEVEL -lt 3 ]; then
        echo -e "${_COLOR_YELLOW}$@${_COLOR_NORMAL}"
    fi
}

echo_info(){
    if [ $_LOG_LEVEL -gt 0 ] && [ $_LOG_LEVEL -lt 2 ]; then
        echo -e "${_COLOR_LIGHTBLUE}$@${_COLOR_NORMAL}"
    fi
}

echo_debug(){
    if [ $_LOG_LEVEL -lt 1 ]; then
        echo -e "${_COLOR_LIGHTGRAY}$@${_COLOR_NORMAL}"
    fi
}
