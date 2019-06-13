""" StrucUFOFDM
---  
Structure for UFOFDM
# --- Syntax 
- nFFT		: FFT size [Int] 
- L			: Filter size [Int]
- allocatedSubcarriers	: Vector of allocated subbcarriers [Array{Int}] 
- sizeRB	: Carrier size in terms of subcarrier (often 12)  [Array{Int}]
- applyPD	: Apply Pre-distortion at Tx stage (default 1, 0 : not applied) [Int=0 or 1] 
- attenuation : dolphChebyshev filter attenation 
- filterTaps  : Filter impulse response coefficient [Array{Float64}]
# --- 
# v 1.0 - Robin Gerzaguet.
"""
struct StrucUFOFDM<: Waveform
	nFFT::Int;
	L::Int;
	allocatedSubcarriers::Array{Int};
	sizeRB::Int;
	applyPD::Int;
	attenuation::Float64;
	cir::Array{Float64};
end

""" initUFOFDM
---  
Create UF-OFDM structure
# --- Syntax 
ufofdm	= initUFOFDM(nFFT,L,allocatedSubcarriers;sizeRB=12,applyPD=1,attenuation=40)
# --- Input parameters 
- nFFT		: FFT size [Int] 
- L			: Filter size [Int]
- allocatedSubcarriers	: Vector of allocated subbcarriers [Array{Int}] 
- sizeRB	: Carrier size in terms of subcarrier (often 12)  [Array{Int}]
- applyPD	: Apply Pre-distortion at Tx stage (default 1, 0 : not applied) [Int=0 or 1] 
- attenuation : dolphChebyshev filter attenation 
- filterTaps  : Filter impulse response coefficient [Array{Float64}]- 
# --- Output parameters 
- ufofdm	: UF-OFDM structure [StrucUFOFDM] 
# --- 
# v 1.0 - Robin Gerzaguet.
"""
function initUFOFDM(nFFT,L,allocatedSubcarriers;sizeRB=12,applyPD=1,attenuation=40)
	# ---Checking FFT size
	if maximum(allocatedSubcarriers) > nFFT
		error("Subcarrier allocation is impossible");
	end
	# --- Create the filter response 
	filterTaps = dolphChebyshev(L,attenuation);
	# --- Create the OFDM structure
	return StrucUFOFDM(nFFT,L,allocatedSubcarriers,sizeRB,applyPD,attenuation,filterTaps);
end



""" ufofdmSigGen
---  
Apply Universal Filtered Orthogonal Frequency Division Multiplexing (UF-OFDM) to the time frequency matrix qamMat and returns a time domain UF-OFDM signal [1,2]
ufofdm is parametrized by its FFT size, the filter length (in samples) and the allocatedSubcarriers vector. Optional parameters are carrier size in subcarrier (by default RB size which is 12) Dolph-Chebyshev window attenuation (40) and predistortion application (set to 1)
# --- Syntax 
sigId	= genereSignalufofdm(qamMat,nFFT,nCp,allocatedSubcarriers;sizeRB=12,applyPD=1,attenuation=40)
# ---  Input parameters
- qamMat  : Time frequency matrix : [Array{Complex{Float64},nbSubcarriers,nbSymb}]
- nbSymb			: Number of ufofdm symbol tro be transmitted
- nbSubcarriers	: Number of allocated subcarriers (shall be < nFFT)
- nFFT	  : FFT size [Int]
- L		  : Dolph Chebyshev filter length [Int]
- allocatedSubcarriers : Vector of index of allocated subcarriers [Array{Int,nbSubcarriers}]
- sizeRB  : Carrier size in subcarriers (default : LTE RB size: 12) [Int]
- applyPD : Filter shape compensation (enabled by default) [Int]
- attenuation : DC filter attenation in dB (default: 90) [Float64]
# ---  Output parameters
- sigId	  : ufofdm signal in time domain [Array{Complex{Float64},nbEch}]
	* nbEch	: Number of samples: nbSymb*(nFFT+L-1)
# References
- [1] R. Gerzaguet and al. The 5G candidate waveform race: a comparison of complexity and performance. EURASIP Journal on Wireless Communications and Networking, 2017
- [2] V. Vakilian and al: Universal-filtered multi-carrier technique for wireless systems beyond LTE. Proc. IEEE Globecom Workshops (GC Wkshps), 2013
# ---
# v 1.0 - Robin Gerzaguet.
"""
function ufofdmSigGen(qamMat,nFFT,L,allocatedSubcarriers;sizeRB=12,applyPD=1,attenuation=40,filterTaps=Array{Float64}(undef,0))
	# ----------------------------------------------------
	# --- Getting filter info
	# ----------------------------------------------------
	if isempty(filterTaps)
		# No filter is given, so create one based on input parameters 
		filterTaps = dolphChebyshev(L,attenuation);
	end
	# ----------------------------------------------------
	# --- UF-OFDM parameters
	# ----------------------------------------------------
	# --- Symbol size (classic convolution)
	sizeSymb	  = nFFT + L - 1;
	nbSymb		  = size(qamMat,2);
	# --- Number of physical RB (i.e carriers)
	nbRB		  = Int(floor(length(allocatedSubcarriers) / sizeRB));
	nbDataSubcarrier = length(allocatedSubcarriers);
	# ----------------------------------------------------
	# --- Initiatiaisation of filter parameters
	# ----------------------------------------------------
	# Purpose is to defined each filter translated at the appropriate carrier frequency (center of carrier group)
	# Init variables
	sF			  = 0;
	carrierRB	  = zeros(Int,nbRB,sizeRB);		# Matrix of carriers (carrier on line, subcarrier on column)
	filterMat	  = zeros(Complex{Float64},nbRB,L);		# Matrix of frequency translated filterStopBand
	# --- Iterative spectrum generation
	for iB1 = 1 : 1 : nbRB
		# --- Getting current RB
		carrierRB[iB1,:]	  = allocatedSubcarriers[1+(iB1-1)*sizeRB:iB1*sizeRB];
		# --- Finding carrier centering
		spectrumLoc			  = carrierRB[iB1,1] + (carrierRB[iB1,end]-carrierRB[iB1,1])/2;
		# --- Setting ones to appropriate spectral location
		# Setting 1 on the carrier to get the amplitude reduction for PD stage
		sigToFFT			  = zeros(Complex{Float64},nFFT);
		sigToFFT[carrierRB[iB1,:]]	  = ones(Complex{Float64},sizeRB);
		# --- Switch to time domain
		sigToFFT			  = ifft(sigToFFT);
		# --- Getting frequency shift filter
		filterMat[iB1,:]      = filterTaps .* (exp.(2*1im*pi*spectrumLoc*collect(0:L-1)/nFFT));
		# --- Apply filter on RB
		sF					  = sF .+ conv(sigToFFT,filterMat[iB1,:]);
	end
	# --- Pre-distortion stage
	if applyPD == 1
		# --- Apply FFT on ZP data
		sigFFT		  = fft([sF;zeros(Complex{Float64},nFFT-L+1)]);
		# --- Channel estimation for current symbol
		sigPD         = sigFFT[1:2:end];
		# --- Deduce pre-distortion filter
		chestPD		  = sigPD[allocatedSubcarriers];
	else
		# --- No predistortion filter
		chestPD		  = ones(Int,nbDataSubcarrier);
	end
	# ----------------------------------------------------
	## --- Signal Generation
	# ----------------------------------------------------
	# --- Init Signal vector
	sigId					= zeros(Complex{Float64},sizeSymb,nbSymb);
	# --- Iterative UFOFDM signal generation
	for iB = 1 : 1 : nbSymb
	    # --- Init sum operator
		filteredSignal		  = zeros(Complex{Float64},nbRB,sizeSymb);
		# --- Pre-disrtorition
		matrixSeqPD			  = qamMat[:,iB] ./ chestPD;
	    # --- Filtering Ressource blocks
	    for iB1 = 1 : 1: nbRB
	        # --- Block Data to send
	        dataBlock			  = matrixSeqPD[1+(iB1-1)*sizeRB:iB1*sizeRB];
	        # --- Setting data to adequate RB
			sigToFFT			  = zeros(Complex{Float64},nFFT);
	        sigToFFT[carrierRB[iB1,:]]	  = dataBlock;
	        # --- IFFT
	        sigIFFT				  = ifft(sigToFFT,1);
	        # --- Apply filter on RB
	        filteredSignal[iB1,:] = conv(sigIFFT,filterMat[iB1,:]);
	    end
	    # --- Output UFOFDM symbol
	    sigId[:,iB]	  = sum(filteredSignal,dims=1);
	end
	sigId = sigId[:];
	return sigId;
end
# --- MD is waveform structure is given


""" ufofdmSigGen
---  
Apply Universal Filtered Orthogonal Frequency Division Multiplexing (UF-OFDM) to the time frequency matrix qamMat and returns a time domain UF-OFDM signal [1,2]
ufofdm is parametrized by its FFT size, the filter length (in samples) and the allocatedSubcarriers vector. Optional parameters are carrier size in subcarrier (by default RB size which is 12) Dolph-Chebyshev window attenuation (40) and predistortion application (set to 1)
# --- Syntax 
sigId	= genereSignalufofdm(qamMat,ufofdm);
# ---  Input parameters
- qamMat  : Time frequency matrix : [Array{Complex{Float64},nbSubcarriers,nbSymb}]
- ufofdm  : UF-OFDM structure [StrucUFOFDM]
# ---  Output parameters
- sigId	  : ufofdm signal in time domain [Array{Complex{Float64},nbEch}]
	* nbEch	: Number of samples: nbSymb*(nFFT+L-1)
# References
- [1] R. Gerzaguet and al. The 5G candidate waveform race: a comparison of complexity and performance. EURASIP Journal on Wireless Communications and Networking, 2017
- [2] V. Vakilian and al: Universal-filtered multi-carrier technique for wireless systems beyond LTE. Proc. IEEE Globecom Workshops (GC Wkshps), 2013
# ---
# v 1.0 - Robin Gerzaguet.
"""
function ufofdmSigGen(qamMat,ufofdm::StrucUFOFDM)
	return ufofdmSigGen(qamMat,ufofdm.nFFT,ufofdm.L,ufofdm.allocatedSubcarriers,sizeRB=ufofdm.sizeRB,applyPD=ufofdm.applyPD,attenuation=ufofdm.attenuation);
end