#! /bin/bash

# Copyright 2017 Ken Sinclair

#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

cleanup() {
	exit_value=$([[ -z "$1" ]] && echo 0 || echo "$1")

	echo -e "\nCleaning up..."

	if [[ ! -z "$files" ]] ; then
		for f in "$files" ; do
			rm $f 2> /dev/null
		done
	fi
	echo -e "Exiting.\n"
	exit "$exit_value"
} ; trap cleanup SIGINT

delfile() {
	files=("${files[@]/$1}")
}

error() {
	errtxt=$([[ -z "$1" ]] && echo "Unexpexted error occured" || echo "$1")
	(1>&2 echo -e "ERROR: $errtxt\nAborting.")
	cleanup "$_exit_err_val"
}

pushfile() {
	files=$([[ -z "$files" ]] && echo "$1" || echo "${files[@]} $1")
}

_exit_val=0
_exit_err_val=99

mrrurl="https://www.archlinux.org/mirrorlist/?country=CA&country=PL&country=RO&country=SI&country=CH&country=UA&country=US&protocol=https&ip_version=4&use_mirror_status=on"

mrrurl=$([[ -z "$1" ]] && echo "$mrrurl" || echo "$1")

echo "Mirror download URL set to ${mrrurl}"

echo -e "Downloading list..."

mrrlst=$(mktemp)
pushfile "$mrrlst"

curl -s "$mrrurl" >> "$mrrlst"

curlrtv="$?"
if [[ "$curlrtv" -ne 0 ]] ; then
	error "cURL error ${curlrtv}.\nError encountered using URL $mrrurl."
fi
if [[ $(wc -l "$mrrlst" | cut -d" " -f1) -eq  0 ]] ; then
	errtxt="Error getting mirror list from \"$mrrurl\"."
	errtxt="${errtxt}\nReceived an empty response."
	error "$errtxt"
fi

numhosts=$(ack -ch https "$mrrlst")

if [[ "$numhosts" -eq 0 ]] ; then
	error "No hosts returned. Perhaps your parameters are too restrictive."
fi

echo -e "Got $numhosts hosts.\n"

echo -e "Testing hosts...\n"

hostlst=$(mktemp)
pushfile "$hostlist"
ack https "$mrrlst" | cut -d= -f2 | cut -d/ -f3 | ack [a-z] >> "$hostlst"

pingout=$(mktemp)
pushfile "$pingout"

numtimeout=0
for hst in `cat "$hostlst"` ; do 
	echo "Testing $hst..."
	p=$(ping -Aq4 -w1 -c5 "$hst" | tail -n1)
	bmark=$(echo "$p" | cut -d= -f2 | cut -d, -f1 | cut -d/ -f2,4)
	if [[ $(echo "$bmark" | ack [0-9]) ]] ; then
		echo "${hst}: $bmark" >> "$pingout"
	else
		echo "TIMEOUT: $hst"
		((numtimeout++))
	fi
done

echo -e "\nOf $numhosts hosts, $numtimeout timed out."

numhosts=$(wc -l "$pingout" | cut -d" " -f1 )

echo "Got $numhosts good hosts."

[[ "$numhosts" -eq 0 ]] && error "All hosts timed out."

echo -e "\nGenerating mirrorlist..."

sort -n -o "$pingout" -k2 "$pingout"
newmrrlst=$(mktemp)
pushfile "$newmrrlst"
for hst in $(cut -d: -f1 "$pingout") ; do
	ack $hst "$mrrlst" | tr -d '#' >> "$newmrrlst"
done

echo "Moving new list to ${HOME}/mirrorlist"
mv -iT "$newmrrlst" ${HOME}/mirrorlist
mvretval="$?"

[[ "$mvretval" -ne 0 ]] && error "Cannot move mirrorlist to home directory."

cleanup "$_exit_val"
