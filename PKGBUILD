# Contributor: Anton Pirogov (anton dot pirogov at gmail dot com)

pkgname=invtxt
pkgver=0.1
pkgrel=1
pkgdesc="home inventory script inspired by todo.txt"
url="http://github.com/apirogov/invtxt"
makedepends=('git')
depends=('ruby')
arch=('any')
license="GPL"

build() {
  git clone https://github.com/apirogov/invtxt.git
  install -D -m755 $srcdir/invtxt/invtxt.rb $pkgdir/usr/bin/invtxt
}
