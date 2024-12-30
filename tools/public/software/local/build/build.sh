if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
#yumdownloader --destdir=$OMW_HOME/packages/rpms --resolve yumdownloader --resolve gtk3-devel libX11-devel libXt-devel libSM-devel libICE-devel libXpm-devel xorg-x11-proto-devel
rm $OMW_HOME/packages/rpms/*i686*

if [ -z $PUBLIC_SOFTWARE ]; then
  echo "PUBLIC_SOFTWARE is not defined"
  exit 1
fi

cd $PUBLIC_SOFTWARE/local
localdir=$PUBLIC_SOFTWARE/local/local-1.0.0
rm -rf $localdir/*
mkdir -p $localdir
cd $localdir
find $OMW_HOME/packages/rpms -maxdepth 1 -name "*.rpm" -print0 | while IFS= read -r -d $'\0' rpm_file; do
    rpm2cpio "$rpm_file" | cpio -idmv
done


