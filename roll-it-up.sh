#!/bin/sh

# This script generates a set of $category/$module and $everything/$module
# links in the current directory, given a list of module versions for this
# release.  See module-list.txt for the last release's list.

individual_dir="/srv/xorg.freedesktop.org/archive/individual/"
relative_dir="../../../individual"

if [ ! -d $individual_dir ]; then
    echo "$i not a suitable base directory for individual packages."
    exit 1
fi

mkdir -p everything

while read name; do
    list=`find $individual_dir -name $name.tar\* `
    if test "x$list" = x; then
	# Since .../xcb is a symlink, find doesn't follow it normally,
	# so explicitly double-check there
	list=`find ${individual_dir}xcb/ -name $name.tar\* `
	if test "x$list" = x; then
	    echo "Couldn't find module ${name}"
	fi
    fi
    for i in $list; do
	i=`echo $i | sed "s|$individual_dir||g"`
	mkdir -p `dirname $i`
	ln -sf $relative_dir/$i $i
	ln -sf $relative_dir/$i everything/`basename $i`
    done
done
