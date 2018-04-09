#!/bin/bash

[ $# -eq 0 ] && { echo "player id is required!"; exit 1; }
[[ "$1" =~ ^[0-9]+$ ]] || { echo "Bad player id"; return; }

plid=$1
pdir=./players
ldir=./locations
CMD=$2

dirmap(){
  local var=""
  case "$1" in
    n) val='north' ;;
    s) val='south' ;;
    w) val='east' ;;
    e) val='west' ;;
    u) val='up' ;;
    d) val='down' ;;
    *) val='error';;
  esac
  printf "$val"
}

[ -e $pdir ] || mkdir $pdir
[ -e $ldir ] || mkdir $ldir

new_player() # id,name,wallet
{
  [[ "$1" =~ ^[0-9]+$ ]] || { echo "Bad player id"; return; }
  [[ "$2" =~ ^[a-zA-Z]{3,18}$ ]] || { echo "Bad player name"; return; }
  [ -d $pdir/$1 ] && { echo "Player with $1 id already exists"; return; }
  mkdir -p $pdir/$1
  printf "$2" > $pdir/$1/name
  printf "$3" > $pdir/$1/address
  printf "1" > $pdir/$1/where
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
  } || ln -sfn ../../../$pdir/1 $new_loc/who
  printf "Empty location" > $new_loc/name
  printf "there's nothing here" > $new_loc/descr
  # unlock location
}

location_new() # direct
{
  local r_dir
  case "$1" in
    n) r_dir='s' ;;
    s) r_dir='n' ;;
    w) r_dir='e' ;;
    e) r_dir='w' ;;
    u) r_dir='d' ;;
    d) r_dir='u' ;;
  esac
  location_create "$r_dir" "`cat $pdir/$plid/where`" "$1"
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
    [ "$my_name" != "$p_name" ] && printf "$p_name" || printf "You"
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

location_connect()
{
  echo "$1 - $2"
}

say()
{
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

[ -d $pdir/$plid ] && {
  name="`cat $pdir/$plid/name`"
  addr="`cat $pdir/$plid/address`"
} || {
  printf "Your name (3-18 chars): "
  read name
  printf "Your wallet: "
  read wallet
  new_player "$plid" "$name" "$wallet" 
}

[ `l_new_id` == "1" ] && location_create



shopt -s extglob
case "$CMD" in
  l|см) location_show "`cat $pdir/$plid/where`" ;;
  ladd\ [nsweun]) location_new "${CMD: -1}";;
  ldel\ [nsweun]) location_remove "${CMD: -1}";;
  lconnect\ [nsweun]\ +([0-9]))
    location_connect `echo "$CMD"|cut -f2 -d" "` `echo "$CMD"|cut -f3 -d" "`
  ;;
  lname\ +([[:print:]])) location_edit "$CMD";;
  ldescr\ *) location_edit "$CMD";;
  [nsweud]) go "$CMD";;
  llist) locations_list;;
  test) ;;
  *) say "$CMD";;
esac
# vim: noai:ts=2 sw=2 et nu autoindent
