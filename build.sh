#!/bin/sh

envoptions() {
cat << EOF
global environment variables you may set:
  CACHE: absolute path to a global autoconf cache
  QUIET: hush the configure script noise
  USE_XCB: set to "NO" to not use or build xcb

global environment variables you may set to replace default functionality:
  ACLOCAL:  alternate invocation for 'aclocal' (default: aclocal)
  MAKE:     program to use instead of 'make' (default: make)
  FONTPATH: font path to use (defaults under: \$PREFIX/\$LIBDIR...)
  LIBDIR:   path under \$PREFIX for libraries (e.g., lib64) (default: lib)
  GITROOT:  path to freedesktop.org git root, only needed for --clone
            (default: git://anongit.freedesktop.org/git)

global environment variables you may set to augment functionality:
  CONFFLAGS:  additional flags to pass to all configure scripts
  CONFCFLAGS: additional compile flags to pass to all configure scripts
  MAKEFLAGS:  additional flags to pass to all make invocations
  PKG_CONFIG_PATH: include paths in addition to:
                   \$DESTDIR/\$PREFIX/share/pkgconfig
                   \$DESTDIR/\$PREFIX/\$LIBDIR/pkgconfig
  LD_LIBRARY_PATH: include paths in addition to:
                   \$DESTDIR/\$PREFIX/\$LIBDIR
  PATH:            include paths in addition to:
                   \$DESTDIR/\$PREFIX/bin
EOF
}

setup_buildenv() {
    export HOST_OS=`uname -s`
    export HOST_CPU=`uname -m`

    export LIBDIR=${LIBDIR:="lib"}

    # Must create local aclocal dir or aclocal fails
    ACLOCAL_LOCALDIR="${DESTDIR}${PREFIX}/share/aclocal"
    $SUDO mkdir -p ${ACLOCAL_LOCALDIR}

    # The following is required to make aclocal find our .m4 macros
    ACLOCAL=${ACLOCAL:="aclocal"}
    export ACLOCAL="${ACLOCAL} -I ${ACLOCAL_LOCALDIR}"

    # The following is required to make pkg-config find our .pc metadata files
    export PKG_CONFIG_PATH=${DESTDIR}${PREFIX}/share/pkgconfig:${DESTDIR}${PREFIX}/${LIBDIR}/pkgconfig${PKG_CONFIG_PATH+:$PKG_CONFIG_PATH}

    # Set the library path so that locally built libs will be found by apps
    export LD_LIBRARY_PATH=${DESTDIR}${PREFIX}/${LIBDIR}${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}

    # Set the path so that locally built apps will be found and used
    export PATH=${DESTDIR}${PREFIX}/bin${PATH+:$PATH}

    # Choose which make program to use
    MAKE=${MAKE:="make"}

    # Set the default font path for xserver/xorg unless it's already set
    if [ -z "$FONTPATH" ]; then
	export FONTPATH="${PREFIX}/${LIBDIR}/X11/fonts/misc/,${PREFIX}/${LIBDIR}/X11/fonts/Type1/,${PREFIX}/${LIBDIR}/X11/fonts/75dpi/,${PREFIX}/${LIBDIR}/X11/fonts/100dpi/,${PREFIX}/${LIBDIR}/X11/fonts/cyrillic/,${PREFIX}/${LIBDIR}/X11/fonts/TTF/"
    fi

    # Create the log file directory
    $SUDO mkdir -p ${DESTDIR}${PREFIX}/var/log
}

failed_components=""
nonexistent_components=""
clonefailed_components=""

failed() {
    if [ -n "${NOQUIT}" ]; then
	echo "***** $1 failed on $2/$3"
	failed_components="$failed_components $2/$3"
    else
	exit 1
    fi
}

checkfortars() {
    M=$1
    C=$2
    case $M in
        "data")
            case $C in
                "cursors") C="xcursor-themes" ;;
                "bitmaps") C="xbitmaps" ;;
            esac
            ;;
        "font")
            if [ "$C" != "encodings" ]; then
                C="font-$C"
            fi
            ;;
        "lib")
            case $C in
                "libXRes") C="libXres" ;;
                "libxtrans") C="xtrans" ;;
            esac
            ;;
        "pixman")
            M="lib"
            C="pixman"
            ;;
        "proto")
            case $C in
                "x11proto") C="xproto" ;;
            esac
            ;;
        "util")
            case $C in
                "cf") C="xorg-cf-files" ;;
                "macros") C="util-macros" ;;
            esac
            ;;
        "xcb")
            case $C in
                "proto") C="xcb-proto" ;;
                "pthread-stubs") M="lib"; C="libpthread-stubs" ;;
                "util") C="xcb-util" ;;
            esac
            ;;
        "xserver")
            C="xorg-server"
            ;;
    esac
    for ii in $M .; do
        for jj in bz2 gz; do
            TARFILE=`ls -1rt $ii/$C-*.tar.$jj 2> /dev/null | tail -n 1`
            if [ -n "$TARFILE" ]; then
                SRCDIR=`echo $TARFILE | sed "s,.tar.$jj,,"`
                if [ ! -d $SRCDIR ]; then
                    TAROPTS=xjf
                    if [ "$jj" = "gz" ]; then
                        TAROPTS=xzf
                    fi
                    tar $TAROPTS $TARFILE -C $ii || failed tar $1 $2
                fi
                return
            fi
        done
    done
}

clone() {
    case $1 in
        "pixman")
        BASEDIR=""
        ;;
        "xcb")
        BASEDIR=""
        ;;
        "mesa")
        BASEDIR=""
        ;;
        "xkeyboard-config")
        BASEDIR=""
        ;;
        *)
        BASEDIR="xorg/"
        ;;
    esac

    DIR="$1/$2"
    GITROOT=${GITROOT:="git://anongit.freedesktop.org/git"}

    if [ ! -d "$DIR" ]; then
        git clone "$GITROOT/$BASEDIR$DIR" "$DIR"
        if [ $? -ne 0 ] && [ ! -d "$DIR" ]; then
            return 1
        fi
    else
        # git cannot clone into an existing directory
	return 1
    fi

    return 0
}

build() {
    if [ -n "$LISTONLY" ]; then
	echo "$1/$2"
	return 0
    fi

    if [ -n "$RESUME" ]; then
	if [ "$RESUME" = "$1/$2" ]; then
	    unset RESUME
	    # Resume build at this module
	else
	    echo "Skipping $1 module component $2..."
	    return 0
	fi
    fi

    SRCDIR=""
    CONFCMD=""
    if [ -f $1/$2/autogen.sh ]; then
        SRCDIR="$1/$2"
        CONFCMD="autogen.sh"
    elif [ -n "$CLONE" ]; then
        clone $1 $2
        if [ $? -ne 0 ]; then
            echo "Failed to clone $1 module component $2. Ignoring."
            clonefailed_components="$clonefailed_components $1/$2"
            if [ -n "$BUILD_ONE" ]; then
                exit 1
            fi
            return
        fi
        SRCDIR="$1/$2"
        CONFCMD="autogen.sh"
    else
        checkfortars $1 $2
        CONFCMD="configure"
    fi

    if [ -z "$SRCDIR" ]; then
        echo "$1 module component $2 does not exist, skipping."
        nonexistent_components="$nonexistent_components $1/$2"
        return
    fi

    echo "Building $1 module component $2..."

    if [ -n "$BUILT_MODULES_FILE" ]; then
        echo "$1/$2" >> $BUILT_MODULES_FILE
    fi

    old_pwd=`pwd`
    cd $SRCDIR || failed cd1 $1 $2

    if [ -n "$PULL" ]; then
	git pull --rebase || failed "git pull" $1 $2
    fi

    # Build outside source directory
    if [ -n "$DIR_ARCH" ] ; then
	mkdir -p "$DIR_ARCH" || failed mkdir $1 $2
	if cd "$DIR_ARCH" ; then :; else
	    failed cd2 $1 $2
	    cd ${old_pwd}
	    return
	fi
    fi

    # Special configure flags for certain modules
    MOD_SPECIFIC=

    if [ "$1" = "lib" ] && [ "$2" = "libX11" ] && [ "${USE_XCB}" = "NO" ]; then
	MOD_SPECIFIC="--with-xcb=no"
    fi

    LIB_FLAGS=
    if [ -n "$LIBDIR" ]; then
        LIB_FLAGS="--libdir=${PREFIX}/${LIBDIR}"
    fi

    # Use "sh autogen.sh" since some scripts are not executable in CVS
    if [ -z "$NOAUTOGEN" ]; then
        sh ${DIR_CONFIG}/${CONFCMD} --prefix=${PREFIX} ${LIB_FLAGS} \
	    ${MOD_SPECIFIC} ${QUIET:+--quiet} \
	    ${CACHE:+--cache-file=}${CACHE} ${CONFFLAGS} "$CONFCFLAGS" || \
	    failed ${CONFCMD} $1 $2
    fi
    ${MAKE} $MAKEFLAGS || failed make $1 $2
    if [ -n "$CHECK" ]; then
        ${MAKE} $MAKEFLAGS check || failed check $1 $2
    fi
    if [ -n "$CLEAN" ]; then
	${MAKE} $MAKEFLAGS clean || failed clean $1 $2
    fi
    if [ -n "$DIST" ]; then
	${MAKE} $MAKEFLAGS dist || failed dist $1 $2
    fi
    if [ -n "$DISTCHECK" ]; then
	${MAKE} $MAKEFLAGS distcheck || failed distcheck $1 $2
    fi
    $SUDO env LD_LIBRARY_PATH=$LD_LIBRARY_PATH ${MAKE} $MAKEFLAGS install || \
	failed install $1 $2

    cd ${old_pwd}

    if [ -n "$BUILD_ONE" ]; then
	echo "Single-component build complete"
	exit 0
    fi
}

# protocol headers have no build order dependencies
build_proto() {
    case $HOST_OS in
        Darwin*)
            build proto applewmproto
        ;;
        CYGWIN*)
            build proto windowswmproto
        ;;
        *)
        ;;
    esac
    build proto bigreqsproto
    build proto compositeproto
    build proto damageproto
    build proto dmxproto
    build proto dri2proto
    build proto fixesproto
    build proto fontsproto
    build proto glproto
    build proto inputproto
    build proto kbproto
    build proto randrproto
    build proto recordproto
    build proto renderproto
    build proto resourceproto
    build proto scrnsaverproto
    build proto videoproto
    build proto x11proto
    build proto xcmiscproto
    build proto xextproto
    build proto xf86bigfontproto
    build proto xf86dgaproto
    build proto xf86driproto
    build proto xf86vidmodeproto
    build proto xineramaproto
    if [ "${USE_XCB}" != "NO" ]; then
	build xcb proto
    fi
}

# bitmaps is needed for building apps, so has to be done separately first
# cursors depends on apps/xcursorgen
# xkbdata is obsolete - use xkbdesc from xkeyboard-config instead
build_data() {
#    build data bitmaps
    build data cursors
}

# All protocol modules must be installed before the libs (okay, that's an
# overstatement, but all protocol modules should be installed anyway)
#
# the libraries have a dependency order:
# xtrans, Xau, Xdmcp before anything else
# fontenc before Xfont
# ICE before SM
# X11 before Xext
# (X11 and SM) before Xt
# Xt before Xmu and Xpm
# Xext before any other extension library
# Xfixes before Xcomposite
# Xp before XprintUtil before XprintAppUtil
#
# If xcb is being used for libX11, it must be built before libX11, but after
# Xau & Xdmcp
#
build_lib() {
    build lib libxtrans
    build lib libXau
    build lib libXdmcp
    if [ "${USE_XCB}" != "NO" ]; then
        build xcb pthread-stubs
	build xcb libxcb
        build xcb util
    fi
    build lib libX11
    build lib libXext
    case $HOST_OS in
        Darwin*)
            build lib libAppleWM
        ;;
        CYGWIN*)
            build lib libWindowsWM
        ;;
        *)
        ;;
    esac
    build lib libdmx
    build lib libfontenc
    build lib libFS
    build lib libICE
    build lib libSM
    build lib libXt
    build lib libXmu
    build lib libXpm
    build lib libXaw
    build lib libXfixes
    build lib libXcomposite
    build lib libXrender
    build lib libXdamage
    build lib libXcursor
    build lib libXfont
    build lib libXft
    build lib libXi
    build lib libXinerama
    build lib libxkbfile
    build lib libXrandr
    build lib libXRes
    build lib libXScrnSaver
    build lib libXtst
    build lib libXv
    build lib libXvMC
    build lib libXxf86dga
    build lib libXxf86vm
    build lib libpciaccess
    build pixman ""
}

# Most apps depend at least on libX11.
#
# bdftopcf depends on libXfont
# mkfontscale depends on libfontenc and libfreetype
# mkfontdir depends on mkfontscale
#
# TODO: detailed breakdown of which apps require which libs
build_app() {
    build app appres
    build app bdftopcf
    build app beforelight
    build app bitmap
    build app editres
    build app fonttosfnt
    build app fslsfonts
    build app fstobdf
    build app iceauth
    build app ico
    build app listres
    build app luit
    build app mkcomposecache
    build app mkfontdir
    build app mkfontscale
    build app oclock
    build app rgb
    build app rendercheck
    build app rstart
    build app scripts
    build app sessreg
    build app setxkbmap
    build app showfont
    build app smproxy
    build app twm
    build app viewres
    build app x11perf
    build app xauth
    build app xbacklight
    build app xbiff
    build app xcalc
    build app xclipboard
    build app xclock
    build app xcmsdb
    build app xconsole
    build app xcursorgen
    build app xdbedizzy
    build app xditview
    build app xdm
    build app xdpyinfo
    build app xdriinfo
    build app xedit
    build app xev
    build app xeyes
    build app xf86dga
    build app xfd
    build app xfontsel
    build app xfs
    build app xfsinfo
    build app xgamma
    build app xgc
    build app xhost
    build app xinit
    build app xinput
    build app xkbcomp
    build app xkbevd
    build app xkbprint
    build app xkbutils
    build app xkill
    build app xload
    build app xlogo
    build app xlsatoms
    build app xlsclients
    build app xlsfonts
    build app xmag
    build app xman
    build app xmessage
    build app xmh
    build app xmodmap
    build app xmore
    build app xprop
    build app xrandr
    build app xrdb
    build app xrefresh
    build app xscope
    build app xset
    build app xsetmode
    build app xsetroot
    build app xsm
    build app xstdcmap
    build app xvidtune
    build app xvinfo
    build app xwd
    build app xwininfo
    build app xwud
#    if [ "${USE_XCB}" != "NO" ]; then
#	build xcb demo
#    fi
}

build_mesa() {
    build mesa drm
    build mesa mesa
}

# The server requires at least the following libraries:
# Xfont, Xau, Xdmcp, pciaccess
build_xserver() {
    build xserver ""
}

build_driver_input() {
    # Some drivers are only buildable on some OS'es
    case $HOST_OS in
	Linux)
	    build driver xf86-input-aiptek
	    build driver xf86-input-evdev
	    build driver xf86-input-joystick
	    ;;
	*BSD*)
	    build driver xf86-input-joystick
	    ;;
	*)
	    ;;
    esac

    # And some drivers are only buildable on some CPUs.
    case $HOST_CPU in
	i*86* | amd64* | x86*64*)
	    build driver xf86-input-vmmouse
	    ;;
	*)
	    ;;
    esac

    build driver xf86-input-acecad
    build driver xf86-input-keyboard
    build driver xf86-input-mouse
    build driver xf86-input-penmount
    build driver xf86-input-synaptics
    build driver xf86-input-void
}

build_driver_video() {
    # Some drivers are only buildable on some OS'es
    case $HOST_OS in
	*FreeBSD*)
	    case $HOST_CPU in
		sparc64)
		    build driver xf86-video-sunffb
		    ;;
		*)
		    ;;
	    esac
	    ;;
	*NetBSD* | *OpenBSD*)
	    build driver xf86-video-wsfb
	    build driver xf86-video-sunffb
	    ;;
	*Linux*)
	    build driver xf86-video-sisusb
	    build driver xf86-video-sunffb
	    build driver xf86-video-v4l
	    build driver xf86-video-xgixp
	    ;;
	*)
	    ;;
    esac

    # Some drivers are only buildable on some architectures
    case $HOST_CPU in
	*sparc*)
	    build driver xf86-video-suncg14
	    build driver xf86-video-suncg3
	    build driver xf86-video-suncg6
	    build driver xf86-video-sunleo
	    build driver xf86-video-suntcx
	    ;;
	i*86* | amd64* | x86*64*)
            build driver xf86-video-i740
            build driver xf86-video-intel
	    ;;
	*)
	    ;;
    esac

    # Some drivers are only buildable on some architectures of some OS's
    case "$HOST_CPU"-"$HOST_OS" in
	i*86*-*Linux*)
	    build driver xf86-video-geode
	    ;;
	*)
	    ;;
    esac

    build driver xf86-video-apm
    build driver xf86-video-ark
    build driver xf86-video-ast
    build driver xf86-video-ati
    build driver xf86-video-chips
    build driver xf86-video-cirrus
    build driver xf86-video-dummy
    build driver xf86-video-fbdev
#    build driver xf86-video-glide
    build driver xf86-video-glint
    build driver xf86-video-i128
    build driver xf86-video-mach64
    build driver xf86-video-mga
    build driver xf86-video-neomagic
    build driver xf86-video-newport
    build driver xf86-video-nv
    build driver xf86-video-qxl
    build driver xf86-video-radeonhd
    build driver xf86-video-rendition
    build driver xf86-video-r128
    build driver xf86-video-s3
    build driver xf86-video-s3virge
    build driver xf86-video-savage
    build driver xf86-video-siliconmotion
    build driver xf86-video-sis
    build driver xf86-video-tdfx
    build driver xf86-video-tga
    build driver xf86-video-trident
    build driver xf86-video-tseng
    build driver xf86-video-vesa
    build driver xf86-video-vmware
    build driver xf86-video-voodoo
    build driver xf86-video-xgi
}

# The server must be built before the drivers
build_driver() {
    # XQuartz doesn't need these...
    case $HOST_OS in
        Darwin*) return 0 ;;
    esac

    build_driver_input
    build_driver_video
}

# All fonts require mkfontscale and mkfontdir to be available
#
# The following fonts require bdftopcf to be available:
#   adobe-100dpi, adobe-75dpi, adobe-utopia-100dpi, adobe-utopia-75dpi,
#   arabic-misc, bh-100dpi, bh-75dpi, bh-lucidatypewriter-100dpi,
#   bh-lucidatypewriter-75dpi, bitstream-100dpi, bitstream-75dpi,
#   cronyx-cyrillic, cursor-misc, daewoo-misc, dec-misc, isas-misc,
#   jis-misc, micro-misc, misc-cyrillic, misc-misc, mutt-misc,
#   schumacher-misc, screen-cyrillic, sony-misc, sun-misc and
#   winitzki-cyrillic
#
# The font util component must be built before any of the fonts, since they
# use the fontutil.m4 installed by it.   (As do several other modules, such
# as libfontenc and app/xfs, which is why it is moved up to the top.)
#
# The alias component is recommended to be installed after the other fonts
# since the fonts.alias files reference specific fonts installed from the
# other font components
build_font() {
    build font encodings
    build font adobe-100dpi
    build font adobe-75dpi
    build font adobe-utopia-100dpi
    build font adobe-utopia-75dpi
    build font adobe-utopia-type1
    build font arabic-misc
    build font bh-100dpi
    build font bh-75dpi
    build font bh-lucidatypewriter-100dpi
    build font bh-lucidatypewriter-75dpi
    build font bh-ttf
    build font bh-type1
    build font bitstream-100dpi
    build font bitstream-75dpi
    build font bitstream-speedo
    build font bitstream-type1
    build font cronyx-cyrillic
    build font cursor-misc
    build font daewoo-misc
    build font dec-misc
    build font ibm-type1
    build font isas-misc
    build font jis-misc
    build font micro-misc
    build font misc-cyrillic
    build font misc-ethiopic
    build font misc-meltho
    build font misc-misc
    build font mutt-misc
    build font schumacher-misc
    build font screen-cyrillic
    build font sony-misc
    build font sun-misc
    build font winitzki-cyrillic
    build font xfree86-type1
    build font alias
}

# makedepend requires xproto
build_util() {
    build util cf
    build util imake
    build util makedepend
    build util gccmakedep
    build util lndir

    build xkeyboard-config ""
}

# xorg-docs requires xorg-sgml-doctools
build_doc() {
    build doc xorg-sgml-doctools
    build doc xorg-docs
}

usage() {
    echo "Usage: $0 [options] prefix"
    echo "  where options are:"
    echo "  -a : do NOT run auto config tools (autogen.sh, configure)"
    echo "  -b : use .build.$HAVE_ARCH build directory"
    echo "  -c : run make clean in addition to others"
    echo "  -d : run make distcheck in addition to others"
    echo "  -D : run make dist in addition to others"
    echo "  -f file: append module being built to file. The last line of this"
    echo "           file can be used for resuming with -r."
    echo "  -g : build with debug information"
    echo "  -h | --help : display this help and exit successfully"
    echo "  -l : build libraries only (i.e. no drivers, no docs, etc.)"
    echo "  -n : do not quit after error; just print error message"
    echo "  -o module/component : build just this component"
    echo "  -p : run git pull on each component"
    echo "  -r module/component : resume building with this component"
    echo "  -s sudo-command : sudo command to use"
    echo "  --clone : clone non-existing repositories (uses \$GITROOT if set)"
    echo "  --autoresume file : autoresume from file"
    echo "  --check : run make check in addition to others"
    echo ""
    echo "Usage: $0 -L"
    echo "  -L : just list modules to build"
    echo ""
    envoptions
}

HAVE_ARCH="`uname -i`"
DIR_ARCH=""
DIR_CONFIG="."
LIB_ONLY=0

# Process command line args
while [ $# != 0 ]
do
    case $1 in
    -a)
	NOAUTOGEN=1
	;;
    -b)
	DIR_ARCH=".build.$HAVE_ARCH"
	DIR_CONFIG=".."
	;;
    -c)
	CLEAN=1
	;;
    --check)
	CHECK=1
	;;
    --clone)
	CLONE=1
	;;
    -d)
	DISTCHECK=1
	;;
    -D)
	DIST=1
	;;
    -f)
        shift
        BUILT_MODULES_FILE=$1
        ;;
    -g)
	CFLAGS="-g3 -O0"
	export CFLAGS
	CONFCFLAGS="CFLAGS=-g3 -O0"
	;;
    -h|--help)
	usage
	exit 0
	;;
    -l)
	LIB_ONLY=1
	;;
    -n)
	NOQUIT=1
	;;
    -o)
	shift
	RESUME=$1
	BUILD_ONE=1
	;;
    -p)
	PULL=1
	;;
    -r)
	shift
	RESUME=$1
	;;
    --autoresume)
	shift
	BUILT_MODULES_FILE=$1
	[ -f $1 ] && RESUME=`tail -n 1 $1`
	;;
    -s)
	shift
	SUDO=$1
	;;
    -L)
	LISTONLY=1
	;;
    *)
	PREFIX=$1
	;;
    esac

    shift
done

if [ -z "${PREFIX}" ] && [ -z "$LISTONLY" ]; then
    usage
    exit
fi

if [ -z "$LISTONLY" ]; then
    setup_buildenv
    echo "Building to run $HOST_OS / $HOST_CPU ($HOST)"
    date
fi

# We must install the global macros before anything else
build util macros
build font util

build_proto
build_lib
build_mesa

if [ $LIB_ONLY -eq 0 ]; then
    build_doc
    build data bitmaps
    build_app
    build_xserver
    build_driver
    build_data
    build_font
    build_util
fi

if [ -n "$LISTONLY" ]; then
    exit 0
fi

date

if [ -n "$nonexistent_components" ]; then
    echo ""
    echo "***** Skipped components (not available) *****"
    echo "$nonexistent_components"
    echo ""
fi

if [ -n "$failed_components" ]; then
    echo ""
    echo "***** Failed components *****"
    echo "$failed_components"
    echo ""
fi

if [ -n "$CLONE" ] && [ -n "$clonefailed_components" ];  then
    echo ""
    echo "***** Components failed to clone *****"
    echo "$clonefailed_components"
    echo ""
fi

