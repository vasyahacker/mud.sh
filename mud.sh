#!/usr/bin/env bash

hd=~/.mudsh             # home dir
WorldName=$hd/WorldName # world name
pdir=$hd/players        # players dir
ldir=$hd/locations      # locations dir
online=$hd/online       # on-line players dir
SHELL=true              # default shell mode
TPort=false             # TCP port for telnet service
TPortFile=$hd/tport     # Saved TPort to disable UPnP
TSPidFile=$hd/tspid     # Telnet service process id
MyLocalIp=false         # Local ip for UPnP
passfile=$hd/.passwd    # users and passwords
lpid=""                 # message listener process id
platform='unknown'
unamestr=`uname`
MD5="md5"
md5_opts=''

[ -e $WorldName ] && wName="`cat $WorldName`"

[ "$unamestr" == "Linux" ] && { MD5="md5sum"; md5_opts='--'; platform='linux'; }
[ "$unamestr" == 'Darwin' ] && { platform='darwin'; }
[ "$unamestr" == 'FreeBSD' ] && { platform='freebsd'; }

usage()
{
  cat <<-EOF

USAGE: mud.sh <OPTIONS>

OPTIONS

  -pid=ID          Player id
  -cmd=COMMAND     Send game command
  -ns | --no-shell Dont run the shell mode
  -ltp=PORT        Listen TCP PORT and start telnet service
  -upnp            Use UPnP for share your port to world
  -tstop           Stop telnet service

EOF
  return
}

for i in "$@"
do
case $i in
    -pid=*)
      plid="${i#*=}"
      [[ "$plid" =~ ^[0-9a-zA-Z]{3,18}@[a-z]+$ ]] || {
        echo "Bad player id"
        exit 1
      }
      shift
    ;;
      -cmd=*)
      CMD="${i#*=}"
      shift
    ;;
      -ltp=*)
      TPort="${i#*=}"
      [[ "$TPort" =~ ^[0-9]{2,5}$ ]] || { echo "Bad port number"; exit 1; }
      type socat >/dev/null 2>&1 || {
        echo "socat needed for listen TCP port"
        echo "Install socat please"
        exit 1
      }
      shift
    ;;
    -ns|--no-shell)
      SHELL=false
      shift
    ;;
    -upnp)
      type upnpc >/dev/null 2>&1 || {
        echo "upnpc needed for port forward"
        echo "install miniupnpc please"
        exit 1
      }
      MyLocalIp=( `ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -vE '^127\.'` )
      adrnum=${#MyLocalIp[@]}
      [ "$adrnum" = "1" ] || {
        for (( i = 0; i < $adrnum; i++ )); do
          echo "$((i+1)) - ${MyLocalIp[i]}"
        done
        until
          printf "Choice your LAN ip address (1-$adrnum): "
          read num
          [[ "$num" =~ ^[0-9]{1,2}$ ]] && [ $num -ge 1 ] && [ $num -le $adrnum ]
        do true; done
        MyLocalIp=${MyLocalIp[--num]}
      }
      shift
    ;;
    -tstop)
      [ -e $TSPidFile ] && {
        echo "Stopping telnet service.."
        kill `cat $TSPidFile`
        rm -f $TSPidFile
        rm -f $online/*/msg
        rm -f $online/*
        [ -e $TPortFile ] && {
          echo "Stopping UPnP port forwarding.."
          upnpc -d `cat $TPortFile` TCP
          rm -f $TPortFile
        }
      }
      shift
      exit
    ;;
    -h|--help)
      usage
      shift
      exit
    ;;
    *)
      usage
      exit
    ;;
esac
done


dirmap(){
  case "$1" in
    n) printf 'north';;
    s) printf 'south';;
    w) printf 'west' ;;
    e) printf 'east' ;;
    u) printf 'up'   ;;
    d) printf 'down' ;;
    *) printf 'error';;
  esac
}

new_player() # id,name
{
  [[ "$1" =~ ^[0-9a-zA-Z]{3,18}@[a-zA-Z0-9]+$ ]] || { echo "Bad player id"; return; }
  [[ "$2" =~ ^[a-zA-Z]{3,18}$ ]] || { echo "Bad player name"; return; }
  [ -d $pdir/$1 ] && { echo "Player with $1 id already exist"; return; }
  mkdir -p $pdir/$1
  printf "$2" > $pdir/$1/name
  printf "1"  > $pdir/$1/where
  ln -sfn ../../../players/$plid $ldir/1/who
}

registration(){
  local login
  local domain="$wName"
  local password1
  local password2
  echo "Registration"
  while true
  do
    echo "login must be 3-18 chars or nums"
    printf "login: "
    read login
    grep -q "$login@$domain" "$passfile" && {
      echo "login already exist"
      continue
    }
    [[ "$login" =~ ^[0-9a-zA-Z]{3,18}$ ]] && break
  done
  while true
  do
    printf "password:\e[30;40m"
    read password1
    printf "\e[0mrepeat password:\e[30;40m"
    read password2
    printf "\e[0m"
    [ "$password1" == "$password2" ] && break || {
      echo "Passwords missmatch"
      continue
    }
  done
  echo "$login@$domain:`echo "$password1" | $MD5`" >> $passfile
  plid="$login@$domain"
  until
    printf "Your name (3-18 chars): "
    read name
    [[ "$name" =~ ^[0-9a-zA-Z]{3,18}$ ]]
  do true; done
  new_player "$plid" "$name"
}

login(){
  local login
  local domain="$wName"
  local password
  while [ -z "$plid" ]
  do
    printf "type 'n' for registration or login: "
    read login
    [ "$login" == "n" ] && {
      registration
      return
    }
    printf "password:\e[30;40m"
    read password
    printf "\e[0m"
    grep -q "$login@$domain:`echo "$password" | $MD5`" "$passfile" && {
      plid="$login@$domain"
      break
    } || echo "Login or password incorrect"
  done
}

revese_dir() # direct
{
  case "$1" in
    n) printf 's' ;;
    s) printf 'n' ;;
    w) printf 'e' ;;
    e) printf 'w' ;;
    u) printf 'd' ;;
    d) printf 'u' ;;
    *) printf 'error';;
  esac
}

l_new_id()
{
  local lcnt="`ls -A1 $ldir | sort -g | tail -1`"
  local id=$((lcnt))
  ((id++))
  printf "$id"
}

location_create() # exit_dir, exit_location_id, to_dir
{
  # lock locations
  local new_id=`l_new_id`
  local new_loc=$ldir/$new_id
  mkdir $new_loc
  mkdir $new_loc/who
  [ -n "$2" ] && {
    printf "$2" > $new_loc/exit_$1
    printf "$new_id" > $ldir/$2/exit_$3
  } 
  printf "Empty location" > $new_loc/name
  printf "there's nothing here" > $new_loc/descr
  # unlock locations
}

location_new() # direct
{
  local cur_loc_id=`cat $pdir/$plid/where`
  [ -e $ldir/$cur_loc_id/exit_$1 ] && {
    echo "Exit '$1' already exist"
    return
  }
  local r_dir=`revese_dir $1`
  location_create "$r_dir" "$cur_loc_id" "$1"
  echo "Ok"
}

location_connect() # direction loc_id
{
  local cur_loc_id=`cat $pdir/$plid/where`
  local to_loc=$ldir/$2
  local r_dir=`revese_dir $1`
  [ -e "$to_loc" ] && {
    printf "$cur_loc_id" > $to_loc/exit_$r_dir
    printf "$2" > $ldir/$cur_loc_id/exit_$1
  } || {
    echo "Location with id $2 does not exist"
    return
  }
  echo "Ok"
}

location_show() # id
{
  local l=$ldir/$1
  echo "[`cat $l/name`]"
  echo "`cat $l/descr`"
  [ -n "$(find $l -maxdepth 1 -name 'exit_*' -print -quit)" ] && {
    printf "Exit:"
    for loc in `ls -A1 $l/exit_*`
    do
      local exit_id="`cat $loc`"
      printf " ${loc: -1} - `cat $ldir/$exit_id/name`"
    done
  } || echo "No exit"
  echo
  printf "Here is: "
  local my_name="`cat $pdir/$plid/name`"
  local i=1
  for pf in $l/who/*
  do
    local p_name=`cat $pf/name`
    [ $i -eq 1 ] || printf ", "
    ((i++))

    [ "$my_name" != "$p_name" ] && {
      printf "$p_name"
      [ -e $pf/online ] || printf "(sleeps)"
    } || printf "You"
  done
  echo
}

locations_list()
{
  for id in `ls -A locations`
  do
    echo "$id: `cat $ldir/$id/name`"
  done
}

location_remove() # direction
{
  local dir=$1
  local where="`cat $pdir/$plid/where`"
  local from=$ldir/$where
  [ -e $from/exit_$dir ] && {
    local to_id="`cat $from/exit_$dir`"
    [ $to_id -eq 1 ] && { echo "You can not remove start location"; return; }
    local to_dir=$ldir/$to_id
    [ -n "$(find $to_dir -maxdepth 1 -name 'exit_*' -print -quit)" ] && {
      for loc in `ls -A1 $to_dir/exit_*`
      do
         [ "`cat $loc`" == "$where" ] && continue
         echo "You can't remove `dirmap $dir` location - there is more than one exit"
         return
      done
      [ -z "$(ls -A1 $to_dir/who)" ] && {
        rm -rf $to_dir
        rm $from/exit_$dir
        echo "Ok"
      } || {
        echo "You can't remove `dirmap $dir` location - there are people"
        return
      }

    }
  } || echo "You can't remove location from `dirmap $dir`"
}

location_edit() # CMD
{
  local cmd=`echo "$1" | awk '{print $1;}'`
  local txt=`echo "$1" | cut -f2- -d" "`
  local where="`cat $pdir/$plid/where`"
  [ "$cmd" == "lname" ] && printf "$txt" > $ldir/$where/name
  [ "$cmd" == "ldescr" ] && printf "$txt" > $ldir/$where/descr
  echo "Ok"
}

msg_append(){ #file msg
  # while [ -e $1.lock ]; do sleep 0.4; done;
  # touch $1.lock
  # echo "$2" >> $1
  echo "$2" > $1
  # rm -f $1.lock
}

msg(){ # text
  local where_id="`cat $pdir/$plid/where`"
  local l=$ldir/$where_id
  for pf in $l/who/*
  do
    [ "$pf" != "$l/who/$plid" ] && [ -e $pf/online ] && {
      msg_append "$pf/msg" "$1" &
    }
  done
}

say() # text
{
  [ -z "$1" ] && return
  echo "You say: $1"
  local my_name="`cat $pdir/$plid/name`"
  msg "$my_name say: $1"
}

go() # direction
{
  local dir=$1
  local p_where=$pdir/$plid/where
  local from=$ldir/"`cat $p_where`"
  [ -e $from/exit_$dir ] && {
    local to_id="`cat $from/exit_$dir`"
    local to=$ldir/$to_id
    [ -e $to ] && {
      local my_name="`cat $pdir/$plid/name`"
      echo "You going to `dirmap $dir`"
      msg "$my_name goes to `dirmap $dir`"
      mv $from/who/$plid $to/who/$plid
      printf "$to_id" > $p_where
      local rdir="`revese_dir $dir`"
      msg "$my_name came from the `dirmap $rdir`"
      location_show "$to_id"
    } || {
      echo "error go"
      return
    }
  } || echo "You can't move to `dirmap $dir`"
}

# msg_get_clear(){ # file
#   [ -s $1 ] || return
#   while [ -e $1.lock ]; do sleep 0.4; done
#   touch $1.lock
#   cat $1 
#   > $1
#   rm -f $1.lock
# }

# listener(){
#   local msg=$pdir/$plid/msg
#   [ -e $msg ] || touch $msg 
#   while true; do
#     msg_get_clear $msg &
#     sleep 0.4
#   done
# }

on_line(){
  ln -sfn ../../../players/$plid $ldir/1/who
  ln -sfn ../players/$plid $online
  touch $pdir/$plid/online
  local my_name="`cat $pdir/$plid/name`"
  msg "$my_name woke up"
}

off_line(){
  local my_name="`cat $pdir/$plid/name`"
  msg "$my_name fell asleep"
  rm -f $online/$plid
  rm -f $pdir/$plid/online
  rm -f $pdir/$plid/msg
}

quit(){
  echo
  echo "Good bye! Exiting.."
  off_line
  local myjobs="`jobs -p`"
  kill -SIGPIPE $lpid >/dev/null 2>&1
  kill -9 $lpid >/dev/null 2>&1
  kill -SIGPIPE $myjobs >/dev/null 2>&1
  kill -9 $myjobs >/dev/null 2>&1
  [ "$TPort" != false ] && {
    echo "Stopping telnet service.."
    kill -9 `cat $TSPidFile` >/dev/null 2>&1
    rm -f $TSPidFile
    rm -f $online/*/msg
    rm -f $online/*
  }
  [ "$MyLocalIp" != false ] && {
    echo "Stopping UPnP port forwarding.."
    upnpc -d $TPort TCP
    rm -f $TPortFile
  }
  exit
}

shopt -s extglob
cmd_parser(){
  case "$CMD" in
    l|см) location_show "`cat $pdir/$plid/where`" ;;
    ladd\ [nsewud]) location_new "${CMD: -1}";;
    ldel\ [nsewud]) location_remove "${CMD: -1}";;
    lconnect\ [nsewud]\ +([0-9]))
      location_connect `echo "$CMD"|cut -f2 -d" "` `echo "$CMD"|cut -f3 -d" "`
    ;;
    lname\ +([[:print:]])) location_edit "$CMD";;
    ldescr\ *) location_edit "$CMD";;
    [nsewud]) go "$CMD";;
    llist) locations_list;;
    /exit|/quit) quit;;
    /help|help|\?) help;;
    *) say "$CMD";;
  esac
}

help(){
  cat <<-EOF

HELP

l:
  look around

n: go north
s: go south
e: go east
w: go west
u: go up
d: go down

ladd <direction>:
  add new location at nsewud direction

ldel <direction>:
  delete location at nsewud direction

lconnect <direction> <location id>:
  connect current location to location with id at nsewud direction

lname <new name>:
  rename current location

ldescr <description>:
  set description to current location

llist:
  list of all locations

/quit:
  exit from game

EOF
}


[ -e $hd ] || {
  echo "Creating database in $hd..."
  mkdir -p $pdir
  chmod 700 $pdir
  mkdir $ldir
  mkdir $online
  touch $hd/.passwd
  until
    printf "Your personal world name (3-18 chars): "
    read wName
    [[ "$wName" =~ ^[0-9a-zA-Z]{3,18}$ ]]
  do true; done
  echo "$wName" > $WorldName
  echo "Creating first location.."
  location_create
}

[ "$TPort" != false ] && {
  echo "Starting telnet service, see $hd/socat.log for details"
  [ "$SHELL" == true ] && {
    echo "Run $0 -tstop if you need to stop service in future"
  }
  socat -lf $hd/socat.log -lu -lh TCP4-LISTEN:$TPort,reuseaddr,fork EXEC:"$0" > /dev/null 2>&1 &
  echo "$!" > $TSPidFile
  [ "$MyLocalIp" != false ] && {
    echo "UPnP TCP port $TPort forwarding.."
    upnpc -a $MyLocalIp $TPort $TPort TCP
    echo "$TPort" > $TPortFile
  }
}

[ -z "$plid" ] && [ "$SHELL" == true ] && login

[ "$SHELL" == true ] && {
  
  trap quit SIGHUP SIGINT SIGTERM
  echo "Welcome to the $wName world!"
  echo "Type 'help' if you newbie"
  # listener &
  msgpipe=$pdir/$plid/msg
  mkfifo $msgpipe
  cat < $msgpipe &
  lpid=$!
  while true; do sleep 1; done > $msgpipe &
  on_line
  location_show "`cat $pdir/$plid/where`"
  while true; do read CMD; cmd_parser ;done

} || cmd_parser

# vim: noai:ts=2 sw=2 et nu autoindent