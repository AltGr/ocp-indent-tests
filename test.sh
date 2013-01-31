#!/bin/bash -ue

mkdir -p orig

sources=()
names=()
urls=()
configs=()

while read name url config; do
    if [ $# -eq 0 ] || [[ "$*" =~ "$name" ]]; then
        names+=("$name")
        urls+=("$url")
        configs+=("$config")
    fi
done < sources

for ((i=0; i<${#names[@]}; i++)); do
    url=${urls[i]}
    name=${names[i]}
    if ! [ -d "orig/$name" ]; then
        echo "Downloading $name";
        mkdir -p "orig/$name"
        cd "orig/$name"
        wget "$url"
        tgz=$(ls)
        tar -xzf "$tgz"
        find . ! -type d ! -name \*.ml ! -name \*.mli -delete
        find . -empty -delete
        cd -
    fi
done

for ((i=0; i<${#names[@]}; i++)); do
    name=${names[i]}
    config=${configs[i]}
    echo -n "Indenting all source from $name... "
    for f in $(find orig/$name ! -type d); do
        dest=new/${f#orig/}
        mkdir -p $(dirname $dest)
        ocp-indent $config "$f" > "$dest"
    done
    echo "done"
done
echo

diffcount() {
    [ $# -eq 2 ]
    diff -y --suppress-common-lines -E "$1" "$2" |wc -l
}

printf "Lines indented differently:\n\n"
printf "\e[34m%-20s  %15s  %15s  %15s  %15s\e[m\n" \
    source current/orig new/current new/orig result
for name in ${names[@]}; do
    if ! [ -d current/$name ]; then
        cp -r new/$name current
    fi
    total=0; co=0; no=0; nc=0
    for f in $(find orig/$name ! -type d); do
        f=${f#orig/}
        total=$((total + $(wc -l <orig/$f)))
        co=$((co + $(diffcount current/$f orig/$f)))
        nc=$((nc + $(diffcount new/$f current/$f)))
        no=$((no + $(diffcount new/$f orig/$f)))
    done
    printf "\e[34m%-20s\e[m  %14d%%  %14d%%  %14d%%  \e[%dm%+15d\e[m\n" \
        $name $((co*100/total)) $((nc*100/total)) $((no*100/total)) \
        $(if [ $no -eq $co ]; then echo 33
        elif [ $no -gt $co ]; then echo 31
        else echo 32; fi) \
        $((co - no))
done
