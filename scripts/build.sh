#!/bin/bash
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# felixsim
#
# Richard Beanland, Keith Evans, Rudolf A Roemer and Alexander Hubert
#
# (C) 2013/14, all right reserved
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
#  This file is part of felixsim.
#
#  felixsim is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#  
#  felixsim is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with felixsim.  If not, see <http://www.gnu.org/licenses/>.
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

echo "build script for felix"

version=${1:-0.0}
rls=${2:-0}
build=${3:-0.0}
author=${4:-0}
date=${5:-`date -R | cut -b 1-16`}
time=${6:-`date -R | cut -b 18-31`}

echo "attempting to build version" ${version} "with rls" ${rls} "build" ${build} "for author" ${author} "on" ${date} "at time" ${time} 

sourcedir=`pwd`
samplesdir=${sourcedir}/../samples/

cd ..
targetdir=`pwd`/felix-${version}
[ -d ${targetdir} ] || mkdir ${targetdir}
cd ${sourcedir}

tarball=felix-${version}.tar.bz2

# tag the files with the right version/rls/build/author information

# moves sources
cd ${sourcedir}
cp -vr * ${targetdir}

# moves samples
cd ${targetdir}
mkdir -p samples
cp -vr ${samplesdir} .

cd ${targetdir} 

echo "--- working on files in directory" `pwd`

for file in `find . \( -name "*.f90" -o -name "*.inp" -o -name "makefile*" -o -name "*.mk" -o -name "README.txt" \) -print`; do

    echo $file " updating!"
    sed "s/:VERSION:/${version}/g" $file | sed "s/:DATE:/${date}/g" | sed "s/:TIME:/${time}/g" | sed "s/:RLSTATUS:/${rls}/g" | sed "s/:BUILD:/${build}/g" | sed "s/:AUTHOR:/${author}/g" > $file.tmp 

	mv $file.tmp $file
	#ls $file.tmp $file

done

cd ${targetdir}/samples
echo "--- working on files in directory" `pwd`
for sample in *; do
   echo ${sample}
   zip -vrm ${sample}.zip ${sample}/
   #rm -rf ${sample}
done

# create the tarball for OBS deployment

cd ${targetdir}
pwd
cd ..
#cp -vr ${sourcedir}/* ${targetdir}

echo "--- creating tarball" ${tarball} "from files in" ${targetdir}
tar -cjf ${tarball} `basename ${targetdir}`
ls
echo --- tarball now here: ../*.tar.bz2
