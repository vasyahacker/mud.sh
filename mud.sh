#!/usr/bin/env bash

HD=~/.mudsh                   # Home dir
WNAME_FILE=$HD/WorldName      # World name file
PDIR=$HD/players              # Players dir

[ -e $WNAME_FILE ] && WNAME="`cat $WNAME_FILE`"

LDIR=$HD/locations/$WNAME     # Locations dir
ONLINE=$HD/online             # On-line players dir
SHELL=true                    # Shell mode by default
SPORT=false                   # TCP port for node sync service
SPID_FILE=$HD/run/spid        # Node sync service socat process id
TPORT=false                   # TCP port for telnet service
TSPID_FILE=$HD/run/tspid      # Telnet socat service process id
MY_IP=false                   # Local ip for UPnP
PORTS_FILE=$HD/tports         # Saved listening tcp ports for disable UPnP
PASS_FILE=$HD/.passwd         # Users and passwords
LPID=""                       # Message listener process id
PLID=""                       # Player id
RIGHTS=""                     # User access level
MY_NAME=""                    # Current user name
MY_GENDER=""                  # Current user gender
NODES=$HD/nodes               # Nodes dir
CMD_HISTORY=$HD/.cmd_history  # Shell commands history dir
RE_LOGIN='[0-9a-zA-Z]{3,18}'  # Regular expression for validate login
RE_WNAME=$RE_LOGIN            # Reg exp for valid world name
RE_NAME=$RE_LOGIN             # Reg exp for valid player name
platform='unknown'
unamestr="`uname`"
MD5="md5"
md5_opts=''

[ "$unamestr" == "Linux" ] && { MD5='md5sum'; md5_opts='--'; platform='linux'; }
[ "$unamestr" == "Darwin" ] && { platform='darwin'; }
[ "$unamestr" == "FreeBSD" ] && { platform='freebsd'; }

usage()
{
  cat <<-EOF

USAGE: mud.sh <OPTIONS>

OPTIONS

  --pid=ID          Player id
  --cmd=COMMAND     Send game command
  -ns | --no-shell  Dont run the shell mode
  --sport=PORT      Listen TCP PORT and start node sync service
  --ltp=PORT        Listen TCP PORT and start telnet service
  -upnp             Use UPnP for share your port to world
  stop              Stop all services

EOF
  return
}

check_socat()
{
  type socat >/dev/null 2>&1 || {
    echo "socat needed for listen TCP port"
    echo "Install socat please"
    exit 1
  }
}

check_port()
{
  [[ "$1" =~ ^[0-9]{2,5}$ ]] && [ $1 -ge 1024 ] && [ $1 -le 65535 ] && return
  echo "Bad port number (1024-65535 allowed)"
  exit 1;
}

for i in "$@"
do
case $i in
    -pid=*)
      PLID="${i#*=}"
      [[ "$PLID" =~ ^[0-9a-zA-Z]{3,18}@[0-9a-zA-Z]{3,18}$ ]] || {
        echo "Bad player id"
        exit 1
      }
      shift
    ;;
    -cmd=*)
      CMD="${i#*=}"
      shift
    ;;
    -sport=*)
      SPORT="${i#*=}"
      check_port "$SPORT"
      check_socat
      shift
    ;;
    -ltp=*)
      TPORT="${i#*=}"
      check_port "$TPORT"
      check_socat
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
      MY_IP=( `ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | \
        grep -Eo '([0-9]*\.){3}[0-9]*' | grep -vE '^127\.'` )
      adrnum=${#MY_IP[@]}
      [ "$adrnum" = "1" ] || {
        for (( i = 0; i < $adrnum; i++ )); do
          echo "$((i+1)) - ${MY_IP[i]}"
        done
        until
          printf "Choice your LAN ip address (1-$adrnum): "
          read -e num
          [[ "$num" =~ ^[0-9]{1,2}$ ]] && [ $num -ge 1 ] && [ $num -le $adrnum ]
        do true; done
        MY_IP=${MY_IP[--num]}
      }
      shift
    ;;
    stop)
      [ -e $SPID_FILE ] && {
        echo "Stopping node sync service.."
        kill `cat $SPID_FILE`
        rm -f $SPID_FILE
      }
      [ -e $TSPID_FILE ] && {
        echo "Stopping telnet service.."
        kill `cat $TSPID_FILE`
        rm -f $TSPID_FILE
      }
      rm -f $ONLINE/*/msg
      rm -f $ONLINE/*
      [ -e $PORTS_FILE ] && {
        echo "Stopping UPnP port forwarding.."
        for port in `cat $PORTS_FILE`; do
          echo "Stopping port $port UPnp"
          upnpc -d $port TCP
        done
        rm -f $PORTS_FILE
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

trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  echo -n "$var"
}

# formated text block
ftb() {
  fmt -w 63 | pr -t -o 2
}

# description parser
dparser()
{
  #IFS= read descr
  local nameexp="s/~name~/$MY_NAME/g
    s/~kto~/$MY_NAME/g
    s/~kogo~/$MY_NAME/g
    s/~komu~/$MY_NAME/g
    s/~kem~/$MY_NAME/g
    s/~okom~/$MY_NAME/g
    s/~chey~/$MY_NAME/g" 
  [ "$MY_GENDER" == "female" ] && sed "s/{{[^}]*}}//g; s/\[\[//g; s/\]\]//g; $nameexp" | ftb
  [ "$MY_GENDER" == "male" ]   && sed "s/\[\[[^]]*\]\]//g; s/{{//g; s/}}//g; $nameexp" | ftb
}

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

new_player() # id,name,gender
{
  [[ "$1" =~ ^[0-9a-zA-Z]{3,18}@[a-zA-Z0-9]{3,18}$ ]] || { echo "Bad player id"; return; }
  [[ "$2" =~ ^[0-9a-zA-Z]{3,18}$ ]] || { echo "Bad player name"; return; }
  [[ "$3" =~ ^male|female$ ]] || { echo "Bad player gender"; return; }
  [ -d $PDIR/$1 ] && { echo "Player with $1 id already exist"; return; }
  mkdir -p $PDIR/$1
  printf "$2" > $PDIR/$1/name
  printf "$3" > $PDIR/$1/gender
  printf "1"  > $PDIR/$1/where # need customize
  ln -sfn ../../../../players/$1 $LDIR/1/who
}

registration(){
  local login
  local password1
  local password2

  echo "Registration"
  while true
  do
    echo "login must be 3-18 chars or nums"
    read -e -p "login: " login
    grep -q "$login:" "$PASS_FILE" && {
      echo "login already exist"
      continue
    }
    [[ "$login" =~ ^[0-9a-zA-Z]{3,18}$ ]] && break
  done
  while true
  do
    read -e -s -p "password:" password1
    echo
    read -e -s -p "repeat password:" password2
    echo
    [ "$password1" == "$password2" ] && break || {
      echo "Passwords missmatch"
      continue
    }
  done
  [ -z "`ls -A $PDIR`" ] && {
    RIGHTS="admin"
    echo "This is first player, granting administrator access"
  } || RIGHTS="user"
  echo "$login:`echo "$password1" | $MD5 $md5_opts`:$RIGHTS" >> $PASS_FILE
  PLID="$login@$WNAME"
  until
    read -e -p "Your name (3-18 chars): " MY_NAME
    echo
    [[ "$MY_NAME" =~ ^[0-9a-zA-Z]{3,18}$ ]]
  do true; done
  until
    read -e -p "Your gender (male or female): " MY_GENDER
    echo
    [[ "$MY_GENDER" =~ ^male|female$ ]]
  do true; done
  touch $CMD_HISTORY/$PLID
  new_player "$PLID" "$MY_NAME" "$MY_GENDER"
}

login(){
  local login
  local password
  while [ -z "$PLID" ]
  do
    echo
    read -e -p "Type 'n' for registration or login: " login
    [ "$login" == "n" ] && {
      registration
      return
    }
    read -e -s -p "password:" password
    password="`echo "$password" | $MD5 $md5_opts`"
    grep -q "$login:$password" "$PASS_FILE" && {
      PLID="$login@$WNAME"
      MY_NAME="`cat $PDIR/$PLID/name`"
      MY_GENDER="`cat $PDIR/$PLID/gender`"
      grep -q "$login:$password:admin" "$PASS_FILE" && {
        RIGHTS="admin"
      } || RIGHTS="user"
      echo
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
  local lcnt="`ls -A1 $LDIR | sort -g | tail -1`"
  local id=$((lcnt))
  ((id++))
  printf "$id"
}

location_create() # exit_dir, exit_location_id, to_dir
{
  # need lock locations
  local new_id=`l_new_id`
  local new_loc=$LDIR/$new_id
  mkdir $new_loc
  mkdir $new_loc/who
  [ -n "$2" ] && {
    printf "$2" > $new_loc/exit_$1
    printf "$new_id" > $LDIR/$2/exit_$3
  } 
  printf "Empty location" > $new_loc/name
  printf "there's nothing here" > $new_loc/descr
  # need unlock locations
}

location_new() # direct
{
  local cur_loc_id=`cat $PDIR/$PLID/where`
  [ -e $LDIR/$cur_loc_id/exit_$1 ] && {
    echo "Exit '$1' already exist"
    return
  }
  local r_dir=`revese_dir $1`
  location_create "$r_dir" "$cur_loc_id" "$1"
  echo "Ok"
}

location_connect() # direction loc_id
{
  local cur_loc_id=`cat $PDIR/$PLID/where`
  local to_loc=$LDIR/$2
  local r_dir=`revese_dir $1`
  [ -e "$to_loc" ] && {
    printf "$cur_loc_id" > $to_loc/exit_$r_dir
    printf "$2" > $LDIR/$cur_loc_id/exit_$1
  } || {
    echo "Location with id $2 does not exist"
    return
  }
  echo "Ok"
}

location_show() # id
{
  local l=$LDIR/$1
  echo "[`cat $l/name`]"
  echo "`cat $l/descr`" | ftb
  ls $l/exit_* > /dev/null 2>&1 && {
    echo "Exit:"
    for loc in `ls -A1 $l/exit_*`
    do
      local exit_id="`cat $loc`"
      local ldir=$LDIR
      [[ "$exit_id" =~ [0-9]{1,9}@[0-9a-zA-Z]{3,18} ]] && {
        # for enother world
        ldir="$HD/locations/`echo "$exit_id"|cut -f2 -d"@"`"
        exit_id="`echo "$exit_id" | cut -f 1 -d @`"
      }
      [ $exit_id -lt 0 ] && {
        printf " `dirmap "${loc: -1}"`\t- closed\n"
      } || printf " `dirmap "${loc: -1}"`\t- `cat $ldir/$exit_id/name`\n"
    done
  } || echo "No exit"
  echo
  printf "Here is: "
  local i=1
  for pf in $l/who/*
  do
    local p_name=`cat $pf/name`
    [ $i -eq 1 ] || printf ", "
    ((i++))

    [ "$MY_NAME" != "$p_name" ] && {
      printf "$p_name"
      [ -e $pf/online ] || printf "(sleeps)"
    } || printf "You"
  done
  echo
}

locations_list()
{
  for id in `ls -A "$LDIR"`
  do
    echo "$id: `cat $LDIR/$id/name`"
  done
}

location_remove() # direction
{
  local dir=$1
  local where="`cat $PDIR/$PLID/where`"
  local from=$LDIR/$where
  [ -e $from/exit_$dir ] && {
    local to_id="`cat $from/exit_$dir`"
    [ $to_id -eq 1 ] && { echo "You can not remove start location"; return; }
    local to_dir=$LDIR/$to_id
    ls $to_dir/exit_* 1> /dev/null 2>&1 && {
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
  local where="`cat $PDIR/$PLID/where`"
  [ "$cmd" == "lname" ] && printf "$txt" > $LDIR/$where/name
  [ "$cmd" == "ldescr" ] && printf "$txt" > $LDIR/$where/descr
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
  local where_id="`cat $PDIR/$PLID/where`"
  local l=$LDIR/$where_id
  for pf in $l/who/*
  do
    [ "$pf" != "$l/who/$PLID" ] && [ -e $pf/online ] && {
      msg_append "$pf/msg" "$1" &
    }
  done
}

say() # text
{
  [ -z "$1" ] && return
  echo "You say: $1"
  msg "$MY_NAME say: $1"
}

go() # direction
{
  local dir=$1
  local p_where=$PDIR/$PLID/where
  local from=$LDIR/"`cat $p_where`"
  [ -e $from/exit_$dir ] && [ "`cat $from/exit_$dir`" -lt 0 ] && {
    echo "`dirmap $dir` way is closed"
    return
  }
  [ -e $from/${dir}od ] && {
    od="`cat $from/${dir}od | dparser`"
    echo "${od%%')><('*}"
    msg "${od#*')><('}"
  }
  [ -e $from/exit_$dir ] && {
    local to_id="`cat $from/exit_$dir`"

    [[ "$to_id" =~ [0-9]{1,9}@[0-9a-zA-Z]{3,18} ]] && {
      # for enother world
      LDIR="$HD/locations/`echo "$exit_id"|cut -f2 -d"@"`"
      to_id="`echo "$exit_id" | cut -f 1 -d @`"
      # need back portal
      # need send player folder
    }

    local to=$LDIR/$to_id
    [ -e $to ] && {
      [ ! -e $from/${dir}od ] && {
        echo "You going to `dirmap $dir`"
        msg "$MY_NAME goes to `dirmap $dir`"
      }
      mv $from/who/$PLID $to/who/$PLID
      printf "$to_id" > $p_where
      local rdir="`revese_dir $dir`"
      [ -e $to/${rdir}id ] && {
        id="`cat $to/${rdir}id | dparser`"
        echo "${id%%')><('*}"
        msg "${id#*')><('}"
        true
      } || msg "$MY_NAME came from the `dirmap $rdir`"
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
#   local msg=$PDIR/$PLID/msg
#   [ -e $msg ] || touch $msg 
#   while true; do
#     msg_get_clear $msg &
#     sleep 0.4
#   done
# }

on_line(){
  ln -sfn ../../../../players/$PLID $LDIR/1/who
  ln -sfn ../players/$PLID $ONLINE
  touch $PDIR/$PLID/online
  msg "$MY_NAME woke up"
}

off_line(){
  msg "$MY_NAME fell asleep"
  rm -f $ONLINE/$PLID
  rm -f $PDIR/$PLID/online
  rm -f $PDIR/$PLID/msg
}

quit(){
  echo
  echo "Good bye! Exiting.."
  off_line
  local myjobs="`jobs -p`"
  kill -SIGPIPE $LPID >/dev/null 2>&1
  kill -9 $LPID >/dev/null 2>&1
  kill -SIGPIPE $myjobs >/dev/null 2>&1
  kill -9 $myjobs >/dev/null 2>&1
  [ "$TPORT" != false ] && {
    echo "Stopping telnet service.."
    kill -9 `cat $TSPID_FILE` >/dev/null 2>&1
    rm -f $TSPID_FILE
    rm -f $ONLINE/*/msg
    rm -f $ONLINE/*
  }
  [ "$SPORT" != false ] && {
    echo "Stopping node sync service.."
    kill -9 `cat $SPID_FILE` >/dev/null 2>&1
    rm -f $SPID_FILE
  }
  [ "$MY_IP" != false ] && {
    echo "Stopping UPnP port forwarding.."
    [ "$TPORT" != false ] && upnpc -d $TPORT TCP
    [ "$SPORT" != false ] && upnpc -d $SPORT TCP
    rm -f $PORTS_FILE
  }
  exit
}

get_remote_locations()
{
  local ans
  local rwname
  read ans
  ans=`trim "$ans"`
  [[ "$ans" =~ ^PING\ [0-9a-zA-Z]{3,18}$ ]] || exit 1
  rwname="`echo $ans | cut -d " " -f 2`"
  [ "$WNAME" == "$rwname" ] && exit 1
  local rldir=$HD/locations/$rwname
  mkdir -p $NODES/$rwname
  mkdir -p $NODES/$rwname/epoints
  echo "$ADDR" > $NODES/$rwname/addr
  mkdir -p $rldir
  echo "PONG $WNAME"
  echo "GETL"
  base64 --decode - | tar xzf - -C $rldir || return 1
}

node_add()
{
  echo "$1"
  export HD
  export WNAME
  export NODES
  export ADDR="$1"
  export -f trim
  export -f get_remote_locations
  socat TCP:$ADDR EXEC:"bash -c get_remote_locations" || {
    echo "Error"
    return
  }
  echo "Ok"
}

nodes_list()
{
  for name in `ls -A "$NODES"`
  do
    local adddr_file=$NODES/$name/addr
    local ip=`cat $adddr_file | cut -f1 -d :`
    local ping=`ping -c1 $ip | grep 'bytes from' | cut -d = -f 4`
    echo "$name: `cat $adddr_file` $ping"
  done
}

node_epoint() # direction, world 
{
  local dir="$1"
  local cur_loc_id=`cat $PDIR/$PLID/where`
  local cur_exit=$LDIR/$cur_loc_id/exit_$dir
  [ -e $cur_exit ] && { echo "Direction '$1' already exist here"; return; }
  local to_world="$2"
  [ ! -e $HD/locations/$to_world -o ! -e $NODES/$to_world ] && {
    echo "World $to_world not exist, use nadd before nconnect"
    return
  }
  local epoint=$NODES/$to_world/epoints/$cur_loc_id
  [ -e $epoint ] && { echo "This enter point already exist"; return; }
  echo "$dir" > $epoint
  echo "Enter point for $to_world created"
}

node_connect() # direction, world
{
  local dir="$1"
  local cur_loc_id=`cat $PDIR/$PLID/where`
  local cur_exit=$LDIR/$cur_loc_id/exit_$dir
  [ -e $cur_exit ] && { echo "Direction '$dir' already exist here"; return; }
  local to_world="$2"
  [ ! -e $HD/locations/$to_world ] && {
    echo "World $to_world not exist, use nadd before nconnect"
    return
  }
  local to_loc=$HD/locations/$to_world/1 
  # TODO change 1 to id allowed from the world admin
  [ ! -e $to_loc ] && {
    echo "Target location not exist"
    return
  }
  echo "1@$to_world" > $cur_exit

#  local r_dir=`revese_dir $dir`
#  [ -e "$to_loc" ] && {
    # printf "$cur_loc_id" > $to_loc/exit_$r_dir
#    printf "$2" > $cur_exit
#  } || {
#    echo "Location with id $2 does not exist"
#    return
#  }

  echo "Ok"
}

shopt -s extglob
cmd_parser(){
  local user_cmd=true
  [ "$RIGHTS" == "admin" ] && {
    user_cmd=false
    case "$CMD" in
      ladd\ [nsewud]) location_new "${CMD: -1}";;
      ldel\ [nsewud]) location_remove "${CMD: -1}";;
      lconnect\ [nsewud]\ +([0-9]))
        location_connect `echo "$CMD"|cut -f2 -d" "` `echo "$CMD"|cut -f3 -d" "`
      ;;
      lname\ +([[:print:]])) location_edit "$CMD";;
      ldescr\ *) location_edit "$CMD";;
      llist) locations_list;;

      nadd\ +([0-9\.a-zA-Z:])) node_add "`echo "$CMD"|cut -f2 -d' '`";;
      nlist) nodes_list;;
      nconnect\ [nsewud]\ *)
        node_connect `echo "$CMD"|cut -f2 -d" "` `echo "$CMD"|cut -f3 -d" "`
      ;;
      nepoint\ [nsewud]\ +([0-9a-zA-Z]))
        node_epoint `echo "$CMD"|cut -f2 -d" "` `echo "$CMD"|cut -f3 -d" "`
      ;;
      *) user_cmd=true
    esac
  }
  [ "$user_cmd" == false ] && return
  case "$CMD" in
    l|см) location_show "`cat $PDIR/$PLID/where`" ;;
    [nsewud]) go "$CMD";;
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

/quit:
  exit from game
EOF
  [ $RIGHTS == "admin" ] && cat <<-EOF

ADMIN COMMANDS

locations:

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
EOF
}

node_sync_srv()
{
  local ans
  echo "PING $WNAME"
  read -n 23 ans
  [[ "$ans" =~ ^PONG\ [0-9a-zA-Z]{3,18}$ ]] || { echo "Error!"; return; }
  local rwname=`echo "$ans" | cut -d " " -f 2`
  local rpid=""
  local rcmd=""
  while true
  do
    read -n 9 ans
    case "$ans" in
      OCHAN) # open play channel
        while true
        do
          read rcmd
          [[ "$rcmd" =~ "^IncomingGuest:[0-9a-zA-Z]{3,18}@[0-9a-zA-Z]{3,18};name;[male|female]$" ]]
          rpid="${od%%':'*}"
          rcmd="${od#*':'}"
          ./mud.sh --no-shell --pid=$rpid --cmd=$rcmd >> RPLAYING-$rpid.log 2>&1 &
        done
      ;;
      GETL) # get locations
        tar czf - -C $HD/locations/$WNAME ./ --owner=0 --group=0 | base64 -
        exit 0
      ;;
      SETL) # send locations
        base64 --decode - | tar xzf - -C $HD/locations/$WNAME
        exit 0
      ;;
      EXIT) exit 0 ;;
      *) echo "Error!" ;;
    esac
  done
}

[ ! -e $HD ] && {
  echo "Creating database in $HD..."
  mkdir -p $PDIR
  mkdir $HD/run
  chmod 700 $HD
  mkdir $ONLINE
  mkdir $NODES
  mkdir $CMD_HISTORY
  touch $HD/.passwd
  until
    printf "Your personal world name (3-18 chars): "
    read -e WNAME
    [[ "$WNAME" =~ ^[0-9a-zA-Z]{3,18}$ ]]
  do true; done
  LDIR=$HD/locations/$WNAME
  mkdir -p $LDIR
  echo "$WNAME" > $WNAME_FILE
  echo "Creating first location.."
  location_create
}

[ "$TPORT" != false ] && {
  echo "Starting telnet service, see $HD/telnet.log for details"
  [ "$SHELL" == true ] && {
    echo "Run $0 -tstop if you need to stop service in future"
  }
  socat -lf $HD/telnet.log -lu -lh \
    TCP4-LISTEN:$TPORT,reuseaddr,pktinfo,fork,crnl \
    EXEC:"$0" > /dev/null 2>&1 &
  echo "$!" > $TSPID_FILE
  [ "$MY_IP" != false ] && {
    echo "UPnP TCP port $TPORT forwarding.."
    upnpc -a $MY_IP $TPORT $TPORT TCP
    echo "$TPORT" >> $PORTS_FILE
  }
}

[ "$SPORT" != false ] && {
  echo "Starting node sync service, see $HD/mode_sync.log for details"
  export HD
  export WNAME
  export -f node_sync_srv
  socat -lf $HD/node_sync.log -lu -lh \
    TCP4-LISTEN:$SPORT,reuseaddr,pktinfo,fork,crnl \
    EXEC:"bash -c node_sync_srv" > /dev/null 2>&1 &
  echo "$!" > $SPID_FILE
  [ "$MY_IP" != false ] && {
    echo "UPnP TCP port $SPORT forwarding.."
    upnpc -a $MY_IP $SPORT $SPORT TCP
    echo "$SPORT" >> $PORTS_FILE
  }
}

[ ! -z "$PLID" ] && {
  MY_NAME="`cat $PDIR/$PLID/name`"
  RIGHTS="user" # fixme
}

[ -z "$PLID" ] && [ "$SHELL" == "true" ] && login

display(){
  local txt
  while true
  do
    IFS= read txt
    printf "\033[s\r\033[1A\n"
    printf "$txt"
    printf "\n>\033[u"
  done
}

[ "$SHELL" == "true" ] && {
  
  trap quit SIGHUP SIGINT SIGTERM
  echo "Welcome to the $WNAME world!"
  echo "Type 'help' if you are newbie"
  # listener &
  msgpipe=$PDIR/$PLID/msg
  mkfifo $msgpipe
  cat < $msgpipe | display &
  LPID=$!
  while true; do sleep 1; done > $msgpipe &
  on_line
  location_show "`cat $PDIR/$PLID/where`"
  HISTCONTROL="ignoreboth:erasedups"
  #shopt -s histappend
  history -r $CMD_HISTORY/$PLID
  #set -o vi
  while true
  do
    #read -e -p $'\033[5m>\033[0m' CMD ; printf "\033[s\033[1A\r\033[K"
    read -e -p ">" CMD ; printf "\033[1A\r\033[K"
    history -s "$CMD"
    cmd_parser
    history -w $CMD_HISTORY/$PLID
  done

} || cmd_parser

# vim: noai:ts=2 sw=2 et nu autoindent