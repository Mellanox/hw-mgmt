#!/bin/bash

patch_dir="../linux-4.19.custom/patches/"
list=`cat $patch_dir/series`
for i in $list;
do
    echo "Applying $i"
    patch -p1 < $patch_dir/$i
done

