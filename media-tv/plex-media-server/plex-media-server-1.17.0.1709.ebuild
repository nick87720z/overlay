# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python2_7 )
inherit eutils user systemd unpacker pax-utils python-single-r1

COMMIT="982421575"

_APPNAME="plexmediaserver"
_USERNAME="plex"
_SHORTNAME="${_USERNAME}"
_FULL_VERSION="${PV}-${COMMIT}"

URI="https://downloads.plex.tv/plex-media-server-new"

DESCRIPTION="A free media library that is intended for use with a plex client."
HOMEPAGE="http://www.plex.tv/"
SRC_URI="
	amd64? ( ${URI}/${_FULL_VERSION}/debian/plexmediaserver_${_FULL_VERSION}_amd64.deb )
	x86? ( ${URI}/${_FULL_VERSION}/debian/plexmediaserver_${_FULL_VERSION}_i386.deb )
"

SLOT="0"
LICENSE="Plex"
RESTRICT="mirror bindist strip"
KEYWORDS="-* ~amd64 ~x86"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

IUSE="pax_kernel system-openssl avahi"

DEPEND="
	pax_kernel? ( sys-apps/fix-gnustack )
	dev-python/virtualenv[${PYTHON_USEDEP}]"

RDEPEND="
	avahi? ( net-dns/avahi )
	system-openssl? ( dev-libs/openssl:0 )
	${PYTHON_DEPS}"

QA_DESKTOP_FILE="usr/share/applications/plexmediamanager.desktop"
QA_PREBUILT="*"
QA_MULTILIB_PATHS=(
	"usr/lib/${_APPNAME}/.*"
	"usr/lib/${_APPNAME}/Resources/Python/lib/python2.7/.*"
)

EXECSTACKED_BINS=( "${ED%/}/usr/lib/plexmediaserver/libgnsdk_dsp.so*" )
BINS_TO_PAX_MARK=(
	"${ED%/}/usr/lib/plexmediaserver/Plex Script Host"
	"${ED%/}/usr/lib/plexmediaserver/Plex Media Scanner"
)
BINS_TO_PAX_CREATE_FLAGS=( "${ED%/}/usr/lib/plexmediaserver/Resources/Python/bin/python" )

S="${WORKDIR}"
PATCHES=(
	"${FILESDIR}/virtualenv_start_pms.patch"
	"${FILESDIR}/plexmediamanager.desktop.new.patch"
	"${FILESDIR}/add_gentoo_profile_as_platform_version.patch"
)

pkg_setup() {
	enewgroup ${_USERNAME}
	enewuser ${_USERNAME} -1 /bin/bash /var/lib/${_APPNAME} "${_USERNAME},video"
	python-single-r1_pkg_setup
}

src_unpack() {
	unpack_deb ${A}
}

src_install() {
	# Move the config to the correct place
	local CONFIG_VANILLA="/etc/default/plexmediaserver"
	local CONFIG_PATH="/etc/${_SHORTNAME}"
	dodir "${CONFIG_PATH}"
	insinto "${CONFIG_PATH}"
	doins "${CONFIG_VANILLA#/}"
	sed -e "s#${CONFIG_VANILLA}#${CONFIG_PATH}/${_APPNAME}#g" -i "${S}"/usr/sbin/start_pms || die

	# Remove Debian specific files
	rm -rf "usr/share/doc" || die

	# Remove buggy openssl library
	if use system-openssl; then
		rm -f usr/lib/plexmediaserver/libssl.so.1.0.0 || die
	fi

	# Copy main files over to image and preserve permissions so it is portable
	cp -rp usr/ "${ED%/}/" || die

	# Make sure the logging directory is created
	local LOGGING_DIR="/var/log/pms"
	dodir "${LOGGING_DIR}"
	chown "${_USERNAME}":"${_USERNAME}" "${ED%/}/${LOGGING_DIR}" || die
	keepdir "${LOGGING_DIR}"

	# Create default library folder with correct permissions
	local DEFAULT_LIBRARY_DIR="/var/lib/${_APPNAME}"
	dodir "${DEFAULT_LIBRARY_DIR}"
	chown "${_USERNAME}":"${_USERNAME}" "${ED%/}/${DEFAULT_LIBRARY_DIR}" || die
	keepdir "${DEFAULT_LIBRARY_DIR}"

	# Install the OpenRC init/conf files depending on avahi.
	if use avahi; then
		doinitd "${FILESDIR}/init.d/${PN}"
	else
		cp "${FILESDIR}/init.d/${PN}" "${S}/${PN}";
		sed -e '/depend/ s/^#*/#/' -i "${S}/${PN}"
		sed -e '/need/ s/^#*/#/' -i "${S}/${PN}"
		sed -e '1,/^}/s/^}/#}/' -i "${S}/${PN}"
		doinitd "${S}/${PN}"
	fi

	doconfd "${FILESDIR}/conf.d/${PN}"

	# Disabling due to Bug 644694
	#_handle_multilib

	# Mask Plex libraries so that revdep-rebuild doesn't try to rebuild them.
	# Plex has its own precompiled libraries.
	_mask_plex_libraries_revdep

	# Install systemd service file
	local INIT_NAME="${PN}.service"
	local INIT="${FILESDIR}/systemd/${INIT_NAME}"
	systemd_newunit "${INIT}" "${INIT_NAME}"

	# Add PaX marking for hardened systems
	if use pax_kernel; then
		_remove_execstack_markings
		_add_pax_markings
		_add_pax_flags
	fi

	einfo "Configuring virtualenv"
	virtualenv -v --no-pip --no-setuptools --no-wheel "${ED%/}"/usr/lib/plexmediaserver/Resources/Python || die
	pushd "${ED%/}"/usr/lib/plexmediaserver/Resources/Python &>/dev/null || die
	find . -type f -exec sed -i -e "s#${D}##g" {} + || die
	popd &>/dev/null || die
}

pkg_postinst() {
	einfo ""
	elog "Plex Media Server is now installed. Please check the configuration file in /etc/${_SHORTNAME}/${_APPNAME} to verify the default settings."
	elog "To start the Plex Server, run 'rc-config start plex-media-server', you will then be able to access your library at http://<ip>:32400/web/"
}

# Disabling the follow function due to Bug 644694.
# We shouldn't register plex libraries in global
# library path since this will cause other packages
# on the system to break.

# Finds out where the library directory is for this system
# and handles ldflags as to not break library dependencies
# during rebuilds.
_handle_multilib() {
	# Prevent revdep-rebuild, @preserved-rebuild breakage
	cat > "${T}"/66plex <<-EOF || die
		LDPATH="${EPREFIX}/usr/$(get_libdir)/plexmediaserver"
	EOF

	doenvd "${T}"/66plex
}

# Adds the precompiled plex libraries to the revdep-rebuild's mask list
# so it doesn't try to rebuild libraries that can't be rebuilt.
_mask_plex_libraries_revdep() {
	dodir /etc/revdep-rebuild/
	echo "SEARCH_DIRS_MASK=\"${EPREFIX}/usr/$(get_libdir)/plexmediaserver\"" > "${ED%/}"/etc/revdep-rebuild/80plexmediaserver
}

# Remove execstack flags from some libraries/executables
# so that it works in hardened setups.
_remove_execstack_markings() {
	for f in "${EXECSTACKED_BINS[@]}"; do
		# Unquoting 'f' so that expansion works.
		fix-gnustack -f ${f} > /dev/null
	done
}

# Add pax markings to some binaries so that they work on hardened setup.
_add_pax_markings() {
	for f in "${BINS_TO_PAX_MARK[@]}"; do
		pax-mark m "${f}"
	done
}

# Create default PaX markings on virtualenvironment's pythin
_add_pax_flags() {
	for f in "${BINS_TO_PAX_CREATE_FLAGS[@]}"; do
		pax-mark c "${F}"
	done
}
