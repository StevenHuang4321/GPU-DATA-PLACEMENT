#!/usr/bin/python

"""
usage: ./analysis.py *.txt dimension 
"""

import sys
import os
import re
from itertools import *
import time
import math
start = time.time()
alfa = 1
dimension =[]# [2,2,2]
sizeof = []#[4, 4, 4]
block_X = []#[3072,3072,3072]
block_Y = []#[256,256,256]
array_size = []
stride = []
for line in open(sys.argv[9],'r'):
 thread = line.strip()
 if thread[0].isdigit():
  thread = thread.split()
  for x in range(0,len(thread)):
   thread[x] = int(thread[x])
  stride.append(thread)
 elif  thread[0] == '[':
  while thread[0]!= ':':
   thread = thread[1:]
  thread = thread[1:]
  thread = thread.split()
  for x in range(0,len(thread)):
   thread[x] = int(thread[x])
  stride.append(thread)
 else: 
  thread = thread.split()
  for i in range(1,len(thread)):
   thread[i] = int(thread[i])
  if thread[0] == "dimension":
   dimension = thread[1:]
  elif thread[0]=="sizeof":
   sizeof = thread[1:]
  elif thread[0] =="block_X":
   block_X = thread[1:]
  elif thread[0] == "block_Y":
   block_Y = thread[1:]
  elif thread[0] == "array_size":
   array_size = thread[1:]
  else:
   continue
stride.sort(
key = lambda l:(l[0],l[1],l[2],l[3],l[4])
)

start2 = time.time()
#############################################################################################################################################################################
#############################################################          Global Memroy  #######################################################################################
############################################################################################################################################################################@
global_size = int(sys.argv[1])
glo_lat = int(sys.argv[2])
L2_size = int(sys.argv[3])
L2_cache_line = int(sys.argv[4])
L2_lat = int(sys.argv[5])
L1_size = int(sys.argv[6])
L1_cache_line = int(sys.argv[7])
L1_lat = int(sys.argv[8])
if L2_cache_line < L1_cache_line:
 L2_cache_line = L1_cache_line
if L2_size == 0:
 L2_cache_line = sizeof[0]
if L1_size == 0:
 L1_cache_line = sizeof[0]
 L1_cache_line = L2_cache_line 
#L1_cache_line = 128
#L1_size = 16*1024
#L2_cache_line = 32
#L2_size = 768*1024
if L2_cache_line < L1_cache_line:
 L2_cache_line = L1_cache_line
L1_lines = L1_size/L1_cache_line
L2_lines = L2_size/L2_cache_line

x=0
printout = "global "
array = int(stride[x][0])
array_next = array
rw = int(stride[x][1])
exp = int(stride[x][2])
loop = int(stride[x][3])
index = int(stride[x][5])
warp = int(stride[x][4])

print1 = 0
cache_line = L1_cache_line
#array_total=[]
total = 0
total_cache_line=0
access = []
access_cache_line = []
collect_cache_line = {}
L1 = []
L2 = []
L1_hit = 0
L2_hit = 0
while x<len(stride):
 array_next = int(stride[x][0])
 rw_next = int(stride[x][1])
 exp_next = int(stride[x][2])
 loop_next = int(stride[x][3])
 warp_next = int(stride[x][4])
 index_next = int(stride[x][5])
 x = x + 1
 #if warp_next >=32:
 # continue
 if (array == array_next):
  if(rw==rw_next and exp==exp_next and loop==loop_next and warp/32==warp_next/32):#(rw*10000000000+exp*100000000+loop*10000+ (warp/32)== rw_next*10000000000+exp_next*10000000+loop_next*10000+warp_next/32):
     
   index = index_next
   if (rw_next == 0) and index_next*sizeof[array_next]/L1_cache_line in L1 and index_next*sizeof[array_next]/cache_line not in collect_cache_line.keys() and  math.fabs(len(L1)-L1.index(index_next*sizeof[array_next]/L1_cache_line)) <= L1_lines:
    L1_hit += 1
    L1.remove(index_next*sizeof[array_next]/L1_cache_line)
    L1.append(index_next*sizeof[array_next]/L1_cache_line)
   else:
    if rw_next == 0:
     if index_next*sizeof[array_next]/L1_cache_line in L1:
      L1.remove(index_next*sizeof[array_next]/L1_cache_line)
     L1.append(index_next*sizeof[array_next]/L1_cache_line)
    if index_next*sizeof[array_next]/L2_cache_line in L2 and index_next*sizeof[array_next]/cache_line not in collect_cache_line.keys()and math.fabs(len(L2)-L2.index(index_next*sizeof[array_next]/L2_cache_line)) <= L2_lines:
       L2_hit += 1
       L2.remove(index_next*sizeof[array_next]/L2_cache_line)
       L2.append(index_next*sizeof[array_next]/L2_cache_line)
    else:
     if index_next*sizeof[array_next]/L2_cache_line in L2:
      L2.remove(index_next*sizeof[array_next]/L2_cache_line)
     L2.append(index_next*sizeof[array_next]/L2_cache_line)

   if index_next*sizeof[array_next]/cache_line not in collect_cache_line.keys():
    collect_cache_line[index_next*sizeof[array_next]/cache_line] = 1
    
  else:
   exp = exp_next
   loop = loop_next
   warp = warp_next
   rw = rw_next
   index = index_next
   access_cache_line.append(1+(len(collect_cache_line)-1)*alfa)
   collect_cache_line={}
   
   if (rw_next == 0) and index_next*sizeof[array_next]/L1_cache_line in L1 and  math.fabs(len(L1)-L1.index(index_next*sizeof[array_next]/L1_cache_line)) <= L1_lines:
    L1_hit += 1
    L1.remove(index_next*sizeof[array_next]/L1_cache_line)
    L1.append(index_next*sizeof[array_next]/L1_cache_line)
   else:
    if rw_next == 0:
     if index_next*sizeof[array_next]/L1_cache_line in L1:
      L1.remove(index_next*sizeof[array_next]/L1_cache_line)
     L1.append(index_next*sizeof[array_next]/L1_cache_line)
    if index_next*sizeof[array_next]/L2_cache_line in L2 and \
       index_next*sizeof[array_next]/cache_line not in collect_cache_line.keys() and \
       math.fabs(len(L2)-L2.index(index_next*sizeof[array_next]/L2_cache_line)) <= L2_lines:
       L2_hit += 1
       L2.remove(index_next*sizeof[array_next]/L2_cache_line)
       L2.append(index_next*sizeof[array_next]/L2_cache_line)
    else:
     if index_next*sizeof[array_next]/L2_cache_line in L2:
      L2.remove(index_next*sizeof[array_next]/L2_cache_line)
     L2.append(index_next*sizeof[array_next]/L2_cache_line)
     
   collect_cache_line[index_next*sizeof[array_next]/cache_line] = 1
    
 else: 
 
  access_cache_line.append(len(collect_cache_line))
  
  for i in access_cache_line:
   total_cache_line += i
  printout = printout +str(total_cache_line)+" "+str(L1_hit)+" "+str(L2_hit)+" "
  array = array_next
  L1 = []
  L2 = []
  L1_hit = 0
  L2_hit = 0

  access_cache_line = []
  collect_cache_line={}
  collect_cache_line[index_next*sizeof[array_next]/cache_line] =1
  
  L1.append(index_next*sizeof[array_next]/L1_cache_line)
  L2.append(index_next*sizeof[array_next]/L2_cache_line)
  exp = exp_next
  loop = loop_next
  warp = warp_next
  rw = rw_next
  total = 0
  total_cache_line=0


access_cache_line.append(1+(len(collect_cache_line)-1)*alfa)

for i in access_cache_line:
 total_cache_line += i
end = time.time()
print (end -start2)
printout = printout +str(total_cache_line)+" "+str(L1_hit)+" "+str(L2_hit)+"\n"
out = open("output.txt",'a')
out.write(printout)
out.close()

