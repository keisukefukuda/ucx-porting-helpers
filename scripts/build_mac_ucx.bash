#!/bin/bash
set -ue

# Obtain the target UCX version
UCX_VERSION=$(cat $(dirname $0)/../ucx_version.txt)

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
  --with-progress64=$PWD/progress64 \
  --disable-shared

# We need some more patches...

gsed -i.bak 's/UCM_MODULE_LDFLAGS =/UCM_MODULE_LDFLAGS =#/' src/ucm/Makefile


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
  make ${MAKE_OPTS:-} SED=gsed -C $TARGET
done

./src/tools/info/ucx_info -c

#$ ./src/tools/info/ucx_info -c
#UCX_NET_DEVICES=all
#UCX_SHM_DEVICES=all
#UCX_ACC_DEVICES=all
#UCX_SELF_DEVICES=all
#UCX_TLS=all
#UCX_ALLOC_PRIO=md:sysv,md:posix,huge,thp,md:*,mmap,heap
#UCX_SOCKADDR_TLS_PRIORITY=rdmacm,tcp,sockcm
#UCX_SOCKADDR_AUX_TLS=ud
#UCX_WARN_INVALID_CONFIG=y
#UCX_BCOPY_THRESH=0
#UCX_RNDV_THRESH=auto
#UCX_RNDV_SEND_NBR_THRESH=256K
#UCX_RNDV_THRESH_FALLBACK=inf
#UCX_RNDV_PERF_DIFF=1.000
#UCX_MULTI_LANE_MAX_RATIO=10.000
#UCX_MAX_EAGER_RAILS=1
#UCX_MAX_RNDV_RAILS=2
#UCX_RNDV_SCHEME=auto
#UCX_RKEY_PTR_SEG_SIZE=512K
#UCX_ZCOPY_THRESH=auto
#UCX_BCOPY_BW=auto
#UCX_ATOMIC_MODE=guess
#UCX_ADDRESS_DEBUG_INFO=n
#UCX_MAX_WORKER_NAME=32
#UCX_USE_MT_MUTEX=n
#UCX_ADAPTIVE_PROGRESS=y
#UCX_SEG_SIZE=8K
#UCX_TM_THRESH=1K
#UCX_TM_MAX_BB_SIZE=1K
#UCX_TM_FORCE_THRESH=8K
#UCX_TM_SW_RNDV=n
#UCX_NUM_EPS=auto
#UCX_NUM_PPN=auto
#UCX_RNDV_FRAG_SIZE=512K
#UCX_RNDV_PIPELINE_SEND_THRESH=inf
#UCX_MEMTYPE_CACHE=y
#UCX_FLUSH_WORKER_EPS=y
#UCX_UNIFIED_MODE=n
#UCX_SOCKADDR_CM_ENABLE=n
#UCX_LISTENER_BACKLOG=auto
#UCX_PROTO_ENABLE=n
#UCX_PROTO_INDIRECT_ID=auto


