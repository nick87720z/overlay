# Copyright 2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="FIRST Robotics Competition control system and programming resources"
HOMEPAGE="https://firstinspires.org/"
SRC_URI="https://github.com/wpilibsuite/allwpilib/releases/download/v${PV}/WPILib_Linux-${PV}.tar.gz"

S="${WORKDIR}"

LICENSE="BSD"
SLOT="$(ver_cut 1)"
KEYWORDS="-* ~amd64"
IUSE=""

DEPEND=""
RDEPEND="${DEPEND}"
BDEPEND=""

RESTRICT="mirror bindist binchecks preserve-libs strip"

src_compile() {
	#no-op
	true
}

src_install() {
	mkdir -p "${D}"/opt/frc"${SLOT}" || die
	cp -a * "${D}"/opt/frc"${SLOT}" || die

	dosym /opt/frc"${SLOT}"/utility/wpilibutility /usr/bin/wpilibutility

	for bin in roborio/bin/*; do
		dosym /opt/frc"${SLOT}"/"$bin" /usr/bin/"$(basename "$bin")"
	done
}
