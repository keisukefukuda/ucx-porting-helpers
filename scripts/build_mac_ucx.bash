#!/bin/bash
set -ue

PROJ_ROOT_DIR=$(cd $(dirname $0)/..; pwd)

# Obtain the target UCX version
UCX_VERSION=$(cat $PROJ_ROOT_DIR/ucx_version.txt)

# Make sure there's no uncomitted changes in ucx/ directory
if [[ -d ucx ]]; then
	cd ucx
	if ! git diff-index --quiet HEAD -- ; then
		# abort
		echo "Error: There is uncomitted changes in ucx/ directory" >&2
		git status
		exit 1
	fi
	cd ..
fi

# First, clone UCX repository

if [[ ! -d ucx ]]; then
	git clone https://github.com/openucx/ucx.git
fi
cd ucx
git fetch origin
git clean -xfd
git checkout $UCX_VERSION
git pull origin $UCX_VERSION


# Fetch a set of patches from our fork
BRANCH_NAME="mac-os-build"
if ! git remote show | grep hiroyuki-sato >/dev/null; then
	git remote add hiroyuki-sato https://github.com/hiroyuki-sato/ucx
fi
git fetch hiroyuki-sato

# Create a new branch to build on MacOS
git branch -D $BRANCH_NAME || :
git checkout -b $BRANCH_NAME
echo ""
echo "***********************************************************************"
echo "*"
echo "* Base commit"
echo "*"
git log -n 1 | awk '{ print "* "$0 }'
echo "***********************************************************************"

# Apply all patches.
for branch in $( git branch -a | grep remotes/hiroyuki-sato/macos/0 | \
                 awk '{ print $NF }' | sort -n ) ; do
  merge_branch=$( echo $branch | sed -e 's/remotes\///' )
  echo ""
  echo "***********************************************************************"
  echo "*"
  echo "* Merge branch $merge_branch "
  echo "*"
  git log -n 1 $merge_branch | awk '{ print "* "$0 }'
  echo "***********************************************************************"
  echo $merge_branch
  git merge --no-ff --no-edit "$merge_branch"
done

git merge --no-ff --no-edit hiroyuki-sato/macos/disable-shm_remap-temp

# Download & build dependency
if [[ ! -d progress64 ]]; then
	git clone https://github.com/ARM-software/progress64
fi
cd progress64; make all; cd ..

# build ucx
./autogen.sh

#
./configure \
  --disable-numa \
  --with-progress64=$PWD/progress64

# We need some more patches...

gsed -i.bak -e '/archive_cmds=/ s/-install_name [^ ]* //' libtool

patch -p1 <$PROJ_ROOT_DIR/scripts/000_cpu_set.patch


#
# For skipping some sub directory like src/tools/perf,
# execute make one by one.
#
TARGETS="
src/ucm
src/ucs
src/uct
src/ucp
src/tools/info
"


# Run make
for TARGET in $TARGETS ; do
  echo "****************************************"
  echo "* BUILD $TARGET"
  echo "****************************************"
  echo ""
  make V=1 ${MAKE_OPTS:-} SED=gsed -C $TARGET
done

# ./src/tools/info/ucx_info -c


