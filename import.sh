#!/usr/bin/env bash
HD=~/.mudsh
LOCS=$HD/locations/`cat $HD/WorldName`
OLDIFS=$IFS
IFS="®" # make sure that the symbol does not occur in your database
NL="|"  # for multiline strings in record
columns=(id name descr nid sid wid eid uid did nod sod wod eod uod dod n s w e u d)
sql="select `( IFS=$','; echo "${columns[*]}" )` from locations;"

sqlite3 --cmd ".separator '$IFS' '$NL'" fdream.db $sql > dump.txt

readrow="read -d \"$NL\" `(IFS=$' '; echo "${columns[*]}")`"
rm -rf $LOCS/*
while eval $readrow
do
	loc=$LOCS/$id
	mkdir $loc
	mkdir $loc/who
	printf "$name" > $loc/name
	printf "$descr" > $loc/descr
	[ -n "$nid" ] && echo "$nid" > $loc/nid
	[ -n "$sid" ] && echo "$sid" > $loc/sid
	[ -n "$wid" ] && echo "$wid" > $loc/wid
	[ -n "$eid" ] && echo "$eid" > $loc/eid
	[ -n "$uid" ] && echo "$uid" > $loc/uid
	[ -n "$did" ] && echo "$did" > $loc/did
	[ -n "$nod" ] && echo "$nod" > $loc/nod
	[ -n "$sod" ] && echo "$sod" > $loc/sod
	[ -n "$wod" ] && echo "$wod" > $loc/wod
	[ -n "$eod" ] && echo "$eod" > $loc/eod
	[ -n "$uod" ] && echo "$uod" > $loc/uod
	[ -n "$dod" ] && echo "$dod" > $loc/dod
	echo "$id"
	[ "$n" -ne "0" ] && echo "$n" > $loc/exit_n
	[ "$s" -ne "0" ] && echo "$s" > $loc/exit_s
	[ "$e" -ne "0" ] && echo "$e" > $loc/exit_e
	[ "$w" -ne "0" ] && echo "$w" > $loc/exit_w
	[ "$u" -ne "0" ] && echo "$u" > $loc/exit_u
	[ "$d" -ne "0" ] && echo "$d" > $loc/exit_d

#	for col in "${columns[@]}"
#	do
#		eval "echo \"$col : \$$col\""
#	done
done < dump.txt
IFS=$OLDIFS
# vim: noai:ts=2 sw=2 et nu autoindent