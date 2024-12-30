#! /bin/bash
WORKSPACE=''
if [ -z $1 ]; then
    WORKSPACE=$PUBLIC_SOFTWARE/local/local-1.0.0
else
    WORKSPACE=$1
fi

echo "[INFO] Starting the workspace: $WORKSPACE"

LIB_PATH=$WORKSPACE/usr/lib64
PKGCONFIG_PATH=$WORKSPACE/usr/lib64/pkgconfig

if [ ! -d $WORKSPACE ]; then
    echo "[ERROR] The workspace is not found"
    exit 1
fi

cd $WORKSPACE || exit 1
#echo "[INFO] Enter the $LIB_PATH directory"
#cd $LIB_PATH || exit 1

# fix soft link
for link in $(find . -type l -name "*.so"); do
    exist=$(readlink -e $link)
    if [ -z $exist ]; then
        target=$(readlink $link)
        new_target=/lib64/$target
        if [ -e $new_target ]; then
            echo "[INFO] Fix the soft link: $link"
            ln -sfn $new_target $link
            echo "[INFO] $link is fixed"
        else
            echo "[ERROR] The target of the soft link is not found: $link"
        fi
    fi
done

#echo "[INFO] Enter the $PKGCONFIG_PATH directory"
#cd $PKGCONFIG_PATH || exit 1

# fix pc file
for pc in $(find . -type f -name "*.pc"); do
    echo "[INFO] Fix the pkg-config file: $pc"
    sed -i 's|=/usr|'=$WORKSPACE/usr'|g' $pc
    echo "[INFO] $pc is fixed"
done