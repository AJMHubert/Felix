#!/usr/bin/python
# -*- coding: utf-8 -*-

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# felixsim
#
# Richard Beanland, Keith Evans, Rudolf A Roemer and Alexander Hubert
#
# (C) 2013/14, all right reserved
#
# Version: :VERSION:
# Date:    :DATE:
# Time:    :TIME:
# Status:  :RLSTATUS:
# Build:   :BUILD:
# Author:  :AUTHOR:
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

from __future__ import division
import os
import sys
import getopt
try:
  import numpy as np
except ImportError:
  print 'Numpy is not installed'
  sys.exit()
try:
  from PIL import Image
except ImportError:
  print 'PIL not installed'
  sys.exit()

inputTypes = [None, 'tif', 'png']
inputBits = [None, '8', '32']


def convert(location, bits, type, recursNo):

  if os.path.exists(location):
    print("Found input " + location),
    fname = location.rstrip(os.path.sep)

  ftype = None
  if os.path.isdir(fname):
    ftype = 0
    print "as folder"
  elif os.path.splitext(fname)[1] == '.bin':
    ftype = 1
    print "as file"

  if ftype is None:
    print "Cannot interperet file/folder input"
    return

  strRecurs = recursNo
  recurs = None
  outType = type
  strbitDepth = bits

  valid = True

  if outType not in inputTypes:
    valid = False
    print 'Output format ' + outType + ' not recognised'

  if strbitDepth not in inputBits:
    valid = False
    print 'Bit depth ' + strbitDepth + ' not allowed'

  if ftype == 1 and strRecurs is not None:
    print 'Recursion depth not used for single file'

  if strRecurs is None:
    strRecurs = '0'

  if strRecurs.isdigit():
    recurs = int(strRecurs)
    if recurs < 0:
      valid = False
      print 'Recursion depth must be positive'
  else:
    valid = False
    print "Recursion depth must be an integer"

  if not valid:
    return

  if outType is None:
    print 'No output format selected, using tiff'
    outType = 'tif'

  if outType == 'png' and strbitDepth is not None:
    strbitDepth = '8'
    print 'Bit depth is not used for png files, ignoring'
  elif outType == 'png' and strbitDepth is None:
    strbitDepth = '8'
  elif strbitDepth is None:
    strbitDepth = '32'
    print 'No tiff bit depth set, using 32-bit'

  if ftype == 0:
    doFolder(fname, outType, int(strbitDepth), recurs)
  elif ftype == 1:
    toTiff(fname, int(strbitDepth), outType)
    return


def doFolder(rootdir, ftype, bits, rec):
  count = 0
  startdepth = rootdir.count(os.path.sep)
  for root, subFolders, files in os.walk(rootdir):
    if root.count(os.path.sep) - startdepth > rec:
      continue
    else:
      print root
      for f in files:
        if os.path.splitext(f)[-1].lower() == '.bin':
          count += 1
          toTiff(root + os.path.sep + f, bits, ftype)
  print 'Converted ' + str(count) + ' files'


def toTiff(fname, bits, ftype):
  sz = os.path.getsize(fname)
  sz = sz / 8  # as inputs are 64-bit
  sz = np.sqrt(sz)

  newName = os.path.splitext(fname)[0] + '.' + ftype

  if not sz.is_integer():
    print fname + ' is not a square image, aborting'
    return

  data = np.fromfile(fname, dtype='float64')
  data.resize(sz, sz)

  if bits == 8:
    output = np.uint8(float2int(data, bits))
  # elif bits == 16:
  #     output = np.uint16(float2int(data, bits))
  elif bits == 32:
    output = data.astype('float32')

  Image.fromarray(output).save(newName)


def float2int(data, bits):  # might be really dodgy?
  data -= np.amin(data, axis=None)
  data = data / (np.amax(data) / (2 ** bits - 1))
  return data
