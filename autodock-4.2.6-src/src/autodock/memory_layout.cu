#include "constants.h"
#include "typedefs.h"
#ifndef CUDA_HEADERS
#include "/pkgs/nvidia-cuda/5.5/include/cuda.h"
#include "/pkgs/nvidia-cuda/5.5/include/cuda_runtime.h"
#endif
#include <stdio.h>
#ifndef _SUPPORT_H
#include "support.h"
#endif
#ifndef CUDA_UTILS_HOST_H
#include "cuda_utils_host.h"
#endif


const int ATOM_SIZE = (6 + MAX_TORS) * 3 * sizeof(Real);
const int MOL_INDV_SIZE = (7 + MAX_TORS) * sizeof(Real) + MAX_ATOMS * ATOM_SIZE;

__device__ Real * globalReals;
__device__ char * globalChars;


/////////////////////***********************************************/////////////////////
///****   THESE ARE THE UTILITY FUNCTIONS TO USE TO ACCESS DATA ON THE GPU    *****/////

__device__ Real * getIndvAttribute(int idx) {
	//all data is packed into array in x,y,z,qw,qx,qy,qz, [torsion data], ......
	//returns the start address, move to next item by adding sizeof(Real)
	return globalReals + (idx * MOL_INDV_SIZE) * sizeof(Real);
}

__device__ Real * getTorsion(int indvIdx, int torsionIdx) {
	//all data is packed into array in x1,y1,z1,theta1, x2,y2, .....
	//returns the start address, move to next item by adding sizeof(Real)
	return globalReals + (indvIdx * MOL_INDV_SIZE + 7 + 4 * torsionIdx) * sizeof(Real);
}

__device__ char*  getAtom(int indvIdx, int atom) {
	//all data is packed into array in c11,c12,...c1MAX_CHARS, c21, c22, c23, ...
	//returns the start address, move to next item by adding sizeof(char)
  return (char*) (globalChars + (indvIdx * MAX_TORS * MAX_CHARS + atom * MAX_CHARS) * sizeof(char));
}

/////////////////////// ^^^^^utility ^^^^^^^ //////////////////////////////
/////////////////////////////////////////////////////////////////////////


// this function allocates memory on the gpu in form of compact arrays
// called globalReals and globalChars. Then it converts a population to array form
// and transfers all the data to the gpu at once

bool allocate_pop_to_gpu(Population & pop_in) {
	//allocates several arrays of various types to be moved to the GPU

	Real * out; // this contains most of the data
	char * atoms; // this contains the atom data

	int pop_size = pop_in.num_individuals();

	gpuErrchk(cudaMalloc((void **) &out, pop_size * MOL_INDV_SIZE));
	gpuErrchk(cudaMalloc((void **) &atoms, pop_size * MAX_ATOMS * MAX_CHARS));

	for (int i = 0; i < pop_size; ++i) {
		if (pop_in[i].mol == NULL) {
			printf("no molecule for individual %d", i);
			return false;
		}

		Molecule * curr = pop_in[i].mol;
	
		int j = MOL_INDV_SIZE * i; //output idx
		
		//xyz of center of mol
		out[j++] = (Real) (curr->S.T.x);
		out[j++] = (Real) (curr->S.T.y);
		out[j++] = (Real) (curr->S.T.z);

		//quaternion wxyz
		out[j++] = (Real) (curr->S.Q.w);
		out[j++] = (Real) (curr->S.Q.x);
		out[j++] = (Real) (curr->S.Q.y);
		out[j++] = (Real) (curr->S.Q.z);
		
		for (int ii = 0; ii < MAX_ATOMS; ++ii) {
			//xyz of the atom
		  out[j++] = (Real) *(curr->crd[3*ii]);
			out[j++] = (Real) *(curr->crd[3*ii +1]);
			out[j++] = (Real) *(curr->crd[3*ii +2]);
			
			//atom torsion vector xyz
			out[j++] = (Real) *(curr->vt[3*ii]);
			out[j++] = (Real) *(curr->vt[3*ii +1]);
			out[j++] = (Real) *(curr->vt[3*ii +2]);

			//atom torsion angle
			out[j++] = (Real) curr->S.tor[ii];

			//atom string
			for (unsigned int cidx = 0; cidx < MAX_CHARS; ++cidx)
				atoms[MAX_CHARS * ii + cidx] = curr->atomstr[ii][cidx];
		}

	}

	//allocate global mem
	gpuErrchk(cudaMalloc ((void **) &globalReals, pop_size * MOL_INDV_SIZE));
	
	gpuErrchk(cudaMalloc ((void **) &globalChars, pop_size * MAX_ATOMS * MAX_CHARS));


	//transfer to GPU
	gpuErrchk(cudaMemcpy(globalReals, out, pop_size * MOL_INDV_SIZE, cudaMemcpyHostToDevice));
	gpuErrchk(cudaMemcpy(globalChars, atoms, pop_size * MAX_ATOMS * MAX_CHARS, cudaMemcpyHostToDevice));

	free(out);
	
	free(atoms);

	return true;
}
