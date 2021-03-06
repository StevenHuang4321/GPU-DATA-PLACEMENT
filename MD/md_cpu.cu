#include <omp.h>
#include <cassert>
#include <cfloat>
#include <cuda_runtime_api.h>
#include <cuda.h>
#include <iostream>
#include <stdio.h>
#include <list>
#include <map>
#include <math.h>
#include <stdlib.h>
#include <vector>
#include <set>
#include <algorithm>
#include <iterator>
#include <fstream>
#include "../include/common.h"
#define K 1
using namespace std;

#define md_NBLOCKS 16*6*2*2*2*2
#define md_BLOCK_SIZE 256
//#define md_SUPER_BLOCKS_PER_SM 4
//int md_SUPER_BLOCKS_PER_SM = 4;

const int md_nBlksPerCluster = 16; 
const int md_nAtom = md_BLOCK_SIZE * md_NBLOCKS;
const float md_cutsq = 16.0f;
const int md_maxNeighbors = 30;
const double md_domainEdge   = 20.0; // Edge length of the cubic domain
const float md_lj1 = 1.5;
const float md_lj2 = 2.0;
const float  md_EPSILON      = 0.1f; // Relative Error between CPU/GPU


inline int * md_myBuildNeighborList_blkSchedule(const int nAtom, float3* position,
        int* neighborList, int blockSz)
{
  vector<int> atomInds(nAtom);
  vector<int> blkInds((nAtom+blockSz-1)/blockSz);
  for(int i=0; i<blkInds.size(); ++i)
    blkInds[i] = i;
  random_shuffle(blkInds.begin(), blkInds.end());

  int *blkOrder = (int*)malloc(blkInds.size()*sizeof(int));
  for(int i=0; i<blkInds.size(); ++i)
    blkOrder[i] = blkInds[i];

  int j=0; 
  for(vector<int>::iterator it=blkInds.begin(); it!=blkInds.end(); ++it)
  {
    int blkInd = *it;
    for(int i=0; i<blockSz; ++i)
      atomInds[j++] = blkInd*blockSz + i;
  }
  int superBlockSz = blockSz * md_nBlksPerCluster;
  // Build Neighbor List
  for (int i = 0; i < nAtom; i++)
  {
    int start = i - i%superBlockSz; //difference is here
    int end = i + (superBlockSz - i%superBlockSz)-1;

    int nNeighbors = 0;
    do {
      int j = start + rand() % superBlockSz;
      if (i == j || j>=nAtom) continue; // An atom cannot be its own neighbor
      neighborList[nNeighbors*nAtom + atomInds[i]] = atomInds[j];
      nNeighbors ++; 
    } while(nNeighbors<md_maxNeighbors);

  }
  return blkOrder;
}

bool md_checkResults(float3* d_force, float3* position, int *neighList, int nAtom)
{
  for (int i = 0; i < nAtom; i++)
  {
    float3 ipos = position[i];
    float3 f = {0.0f, 0.0f, 0.0f};
    int j = 0;
    while (j < md_maxNeighbors)
    {
      int jidx = neighList[j*nAtom + i];
      float3 jpos = position[jidx];
      //if(i == 196)
      // printf("jidx = %d, ipos.x = %f, jpos.x = %f\n", jidx, ipos.x, jpos.x);
      // Calculate distance
      float delx = ipos.x - jpos.x;
      float dely = ipos.y - jpos.y;
      float delz = ipos.z - jpos.z;
      float r2inv = delx*delx + dely*dely + delz*delz;

      // If distance is less than cutoff, calculate force
      if (r2inv < md_cutsq) {

        r2inv = 1.0f/r2inv;
        float r6inv = r2inv * r2inv * r2inv;
        float force = r2inv*r6inv*(md_lj1*r6inv - md_lj2);

        f.x += delx * force;
        f.y += dely * force;
        f.z += delz * force;
      }
      j++;
    }
    //if(i==0)
    //cerr << d_force[i].x << endl;
    // Check the results
    float diffx = (d_force[i].x - f.x) / d_force[i].x;
    float diffy = (d_force[i].y - f.y) / d_force[i].y;
    float diffz = (d_force[i].z - f.z) / d_force[i].z;
    float err = sqrt(diffx*diffx) + sqrt(diffy*diffy) + sqrt(diffz*diffz);
    if (err > (3.0 * md_EPSILON))
    {
      cout << "Test Failed, idx: " << i << " diff: " << err << "\n";
      cout << "f.x: " << f.x << " df.x: " << d_force[i].x << "\n";
      cout << "f.y: " << f.y << " df.y: " << d_force[i].y << "\n";
      cout << "f.z: " << f.z << " df.z: " << d_force[i].z << "\n";
      cout << "Test FAILED\n";
      return false;
    }
  }
  cout << "Test Passed\n";
  return true;
}

void md_kernel_cpu(float3*  force3,
                                  float3*  position,
                                  int neighCount,
                                  int*  neighList,
                                 float cutsq,
                                 float lj1,
                                  float lj2,
                                  int inum)
{
FILE *file = fopen("hha.txt","w");
#pragma omp for
for(int tx=0;tx<256;tx++){
  int idx = tx;

  // Position of this thread's atom
  float3 ipos = position[idx];

fprintf(file,"0 0 0 0 %d %d\n",tx,idx);
  // Force accumulator
  float3 f = {0.0f, 0.0f, 0.0f};


  int j = 0;
  while (j < neighCount)
  {
    int jidx = neighList[j*inum + idx];

fprintf(file,"1 0 0 %d %d %d\n",j,tx,j*inum+idx);
    float3 jpos;
    jpos = position[jidx];

fprintf(file,"0 0 1 %d %d %d\n",j,tx,jidx);

    // Calculate distance
    float delx = ipos.x - jpos.x;
    float dely = ipos.y - jpos.y;
    float delz = ipos.z - jpos.z;
    float r2inv = delx*delx + dely*dely + delz*delz;

    // If distance is less than cutoff, calculate force
    // and add to accumulator
    if (r2inv < cutsq)
    {
      r2inv = 1.0f/r2inv;
      float r6inv = r2inv * r2inv * r2inv;
      float force = r2inv*r6inv*(lj1*r6inv - lj2);

      f.x += delx * force;
      f.y += dely * force;
      f.z += delz * force;
    }
    j++;
  }

  // store the results
  force3[idx] = f;

fprintf(file,"2 1 0 0 %d %d\n",tx,idx);
//if (threadIdx.x==0) atomicAdd(d_flag,1);
}
}

__global__ void md_kernel(float3*  force3,
                                 const float3* __restrict__ position,
                                 const int neighCount,
                                 const int* __restrict__ neighList,
                                 const float cutsq,
                                 const float lj1,
                                 const float lj2,
                                 const int inum)
{
  int idx = blockIdx.x*blockDim.x + threadIdx.x;

  // Position of this thread's atom
  float3 ipos = position[idx];

  // Force accumulator
  float3 f = {0.0f, 0.0f, 0.0f};


  int j = 0; 
  while (j < neighCount)
  {
    int jidx = neighList[j*inum + idx];
    float3 jpos;
    jpos = position[jidx];

    // Calculate distance
    float delx = ipos.x - jpos.x;
    float dely = ipos.y - jpos.y;
    float delz = ipos.z - jpos.z;
    float r2inv = delx*delx + dely*dely + delz*delz;

    // If distance is less than cutoff, calculate force
    // and add to accumulator
    if (r2inv < cutsq)
    {    
      r2inv = 1.0f/r2inv;
      float r6inv = r2inv * r2inv * r2inv;
      float force = r2inv*r6inv*(lj1*r6inv - lj2);

      f.x += delx * force;
      f.y += dely * force;
      f.z += delz * force;
    }    
    j++; 
  }

  // store the results
  force3[idx] = f;
//if (threadIdx.x==0) atomicAdd(d_flag,1);
}

int main(int argc, char **argv) {
struct timespec t1,t2,t3,t4;
clock_gettime(CLOCK_MONOTONIC,&t1);
  cudaSetDevice(0);
  srand(2013);
  float3* md_position;
  float3* md_force;
  int* md_neighborList;

  cudaMallocHost((void**)&md_position, md_nAtom*sizeof(float3));
  cudaMallocHost((void**)&md_force,    md_nAtom*sizeof(float3));
  cudaMallocHost((void**)&md_neighborList, md_nAtom*md_maxNeighbors*sizeof(int));

  // Allocate device memory for position and force
  float3* d_md_force;
  float3* d_md_position;
  cudaMalloc((void**)&d_md_force, md_nAtom*sizeof(float3));
  cudaMemset(d_md_force, 0, md_nAtom*sizeof(float3));
  cudaMalloc((void**)&d_md_position, md_nAtom*sizeof(float3));

  // Allocate device memory for neighbor list
  int* d_md_neighborList;
  cudaMalloc((void**)&d_md_neighborList, md_nAtom*md_maxNeighbors*sizeof(int));

  for (int i = 0; i < md_nAtom; i++)
  {
    md_position[i].x = (float)(drand48() * md_domainEdge);
    md_position[i].y = (float)(drand48() * md_domainEdge);
    md_position[i].z = (float)(drand48() * md_domainEdge);
  }

  md_myBuildNeighborList_blkSchedule(md_nAtom, md_position,
          md_neighborList, md_BLOCK_SIZE);

  cudaMemcpy(d_md_neighborList, md_neighborList, md_maxNeighbors*md_nAtom*sizeof(int), cudaMemcpyHostToDevice);
  cudaMemcpy(d_md_position, md_position, md_nAtom*sizeof(float3), cudaMemcpyHostToDevice);

clock_gettime(CLOCK_MONOTONIC,&t3);
md_kernel_cpu(md_force, md_position, md_maxNeighbors, md_neighborList,
                   md_cutsq, md_lj1, md_lj2, md_nAtom);
clock_gettime(CLOCK_MONOTONIC,&t4);
printf("profiling time: %f\n",t4.tv_sec-t3.tv_sec+(t4.tv_nsec-t3.tv_nsec)/1.e9);
  cudaEvent_t kernel_start, kernel_stop;
  cudaEventCreate(&kernel_start);
  cudaEventCreate(&kernel_stop);
  float kernel_time = 0.0f;

  cudaEventRecord(kernel_start, 0);

  int md_gridSize  = (md_nAtom-1+md_BLOCK_SIZE) / md_BLOCK_SIZE;
    md_kernel<<<md_gridSize, md_BLOCK_SIZE>>>
                  (d_md_force, d_md_position, md_maxNeighbors, d_md_neighborList,
                   md_cutsq, md_lj1, md_lj2, md_nAtom);


  cudaDeviceSynchronize();

  cudaEventRecord(kernel_stop, 0);
  cudaEventSynchronize(kernel_stop);

  // get elapsed time
  kernel_time = 0.0f;
  cudaEventElapsedTime(&kernel_time, kernel_start, kernel_stop);
  kernel_time *= 1.e-3; // Convert to seconds
  
  cout << "kernel exe time: " << kernel_time << endl;

  cudaMemcpy(md_force, d_md_force, md_nAtom*sizeof(float3),
            cudaMemcpyDeviceToHost);

  md_checkResults(md_force, md_position, md_neighborList, md_nAtom);

clock_gettime(CLOCK_MONOTONIC,&t2);
printf("total time: %f\n",t2.tv_sec-t1.tv_sec+(t2.tv_nsec-t1.tv_nsec)/1.e9);
  return 0;
}

