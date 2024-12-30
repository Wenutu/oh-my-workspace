if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $PUBLIC_SOFTWARE ]; then
  echo "PUBLIC_SOFTWARE is not defined"
  exit 1
fi
if [ -f $OMW_HOME/packages/software/ncurses-6.5.tar.gz ]; then
  echo "ncurses-6.5.tar.gz is found"
else
  echo "ncurses-6.5.tar.gz is not found"
  exit 1
fi
if [ -d ./ncurses-6.5 ]; then
  echo "ncurses-6.5 is found"
  echo "Remove the existing ncurses-6.5"
  rm -rf ./ncurses-6.5
fi
echo "Extract ncurses-6.5.tar.gz"
tar -zxf $OMW_HOME/packages/software/ncurses-6.5.tar.gz -C .
cd ncurses-6.5
echo "Install ncurses-6.5 to $PUBLIC_SOFTWARE/ncurses/ncurses-6.5"
echo "Build ncurses-6.5 with normal"
./configure --prefix=$PUBLIC_SOFTWARE/ncurses/ncurses-6.5 --with-normal --disable-widec --with-shared --with-termlib --enable-pc-files --with-pkg-config-libdir=$PUBLIC_SOFTWARE/ncurses/ncurses-6.5/lib/pkgconfig --enable-overwrite
make -j $(($(nproc) / 2)) && make install
echo "Install ncurses to $PUBLIC_SOFTWARE/ncurses/ncurses-6.5"
echo ""
echo "Build ncurses-6.5 with widec"
./configure --prefix=$PUBLIC_SOFTWARE/ncurses/ncurses-6.5 --with-normal --enable-widec --with-shared --with-termlib --enable-pc-files --with-pkg-config-libdir=$PUBLIC_SOFTWARE/ncurses/ncurses-6.5/lib/pkgconfig --enable-overwrite
make -j $(($(nproc) / 2)) && make install
echo "Install ncursesw to $PUBLIC_SOFTWARE/ncurses/ncurses-6.5"