#!/bin/bash

usage()
{
  cat <<-EOF

USAGE: mud.sh <OPTIONS>

OPTIONS

  -pid=ID      Set player id
  -cmd=COMMAND Send game command
  -s | --shell Run in the shell interactive mode

EOF
  return
}
SHELL=false

for i in "$@"
do
case $i in
    -pid=*)
      plid="${i#*=}"
      [[ "$plid" =~ ^[0-9]+$ ]] || { echo "Bad player id"; exit 1; }
      shift
    ;;
      -cmd=*)
      CMD="${i#*=}"
      shift
    ;;
    -s|--shell)
      SHELL=true
      shift
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

[ -z "$plid" ] && { echo "Your player id is required, try -h for help"; exit 1; }

pdir=./players
ldir=./locations

dirmap(){
  local var=""
  case "$1" in
    n) val='north';;
    s) val='south';;
    w) val='east' ;;
    e) val='west' ;;
    u) val='up'   ;;
    d) val='down' ;;
    *) val='error';;
  esac
  printf "$val"
}

[ -e $pdir ] || mkdir $pdir
[ -e $ldir ] || mkdir $ldir

new_player() # id,name
{
  [[ "$1" =~ ^[0-9]+$ ]] || { echo "Bad player id"; return; }
  [[ "$2" =~ ^[a-zA-Z]{3,18}$ ]] || { echo "Bad player name"; return; }
  [ -d $pdir/$1 ] && { echo "Player with $1 id already exist"; return; }
  mkdir -p $pdir/$1
  printf "$2" > $pdir/$1/name
  printf "1"  > $pdir/$1/where
  ln -sfn ../../../$pdir/$plid $ldir/1/who
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
  local new_id=`l_new_id`
  local new_loc=$ldir/$new_id
  # lock locations
  mkdir $new_loc
  mkdir $new_loc/who
  [ -n "$2" ] && {
    printf "$2" > $new_loc/exit_$1
    printf "$new_id" > $ldir/$2/exit_$3
  } || ln -sfn ../../../$pdir/$plid $new_loc/who # only first time
  printf "Empty location" > $new_loc/name
  printf "there's nothing here" > $new_loc/descr
  # unlock location
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
  for pf_name in `ls -A1 $l/who/*/name`
  do
    local p_name=`cat $pf_name`
    [ "$my_name" != "$p_name" ] && printf "$p_name " || printf "You"
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

say()
{
  [ -z "$1" ] && return
  local my_name="`cat $pdir/$plid/name`"
  echo "You say: $1"
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
      echo "You going to `dirmap $dir`"
      mv $from/who/$plid $to/who/$plid
      printf "$to_id" > $p_where
      location_show "$to_id"
    } || {
      echo "error go"
      return
    }
  } || echo "You can't move to `dirmap $dir`"
}

shopt -s extglob
action(){
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
    /exit|/quit) echo "Good bye! Exiting.."; exit;;
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

[ -d $pdir/$plid ] && {
  name="`cat $pdir/$plid/name`"
} || {
  printf "Your name (3-18 chars): "
  read name
  new_player "$plid" "$name" 
}

[ `l_new_id` == "1" ] && location_create

[ "$SHELL" = true ] && {

  echo "Welcome to the mud.sh world!"
  echo "Type 'help' if you newbie"
  location_show "`cat $pdir/$plid/where`"
  while true; do read CMD; action ;done

} || action

# vim: noai:ts=2 sw=2 et nu autoindent