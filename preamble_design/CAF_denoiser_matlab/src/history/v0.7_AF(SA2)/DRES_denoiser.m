% /*********************************************
% 	GIST pop-denoiser Module  (Ver.0.7m)
% 	Target: AF-noise, Pop-noise
% 	2013-11-18
% 	Human Media Communication & Processing(HuCom) Lab.
%
% 	Change Log.
% 				- (V0.1m) Initial release
%               - (v0.2m) Fixed perfect reconstruction condition when
%                         bypassing denoise operation
%               - (v0.2m) Applied BPF signals for both detection and
%                         reconstrudction
%               - (v0.3m) Revised reconstruction algorithm to use only
%                         previous frame
%               - (v0.4m) Tuned static tonal remover considering 300pps AF
%                         noise
%               - (v0.4m) Changed filter types from 5-th order FIR into
%                         optimized IIR
%               - (v0.5m) Revised frame reconstruction algorithm based on
%                         MDCT analysis
%               - (v0.7m) Revised band-pass filtering based on MDCT analysis
%               - (v0.7m) Revised frame-wise operation matched to DSC with
%                         AAC for recording
% ***********************************************/



function DRES_denoiser(prm)

%% Initialization
load('table/rand_table.mat');
input = prm.input;
output = prm.output;
FS = prm.FS;
SIZE_FRAME = prm.SIZE_FRAME;
SIZE_FSHIFT = prm.SIZE_FSHIFT;
LPorder = prm.LPorder;
BP_cutL = prm.BP_cutL;
BP_cutH = prm.BP_cutH;
MEAN_thr = prm.MEAN_thr;
TONE_len = prm.TONE_len;


[s]=wavread(input);
s=floor(s*32767);

size_total = size(s,1);
s_out = zeros(size(s));

%Temporal buffers for operation
s_frame_1d = zeros(SIZE_FRAME,1);
s_frame_2d = zeros(SIZE_FRAME,1);
s_frame_LP_1d = zeros(SIZE_FRAME*2,1);
S_in_1d = zeros(SIZE_FRAME,1);
dres_bp_1d = zeros(SIZE_FRAME*2,1);
notch_cnt = 0;
n_flag_prv = 0;

binL = floor((BP_cutL / FS) * SIZE_FRAME*2);
binH = floor((BP_cutH / FS) * SIZE_FRAME*2);
binL_notch1 = floor((5900 / FS) * SIZE_FRAME*2);
binH_notch1 = floor((6300 / FS) * SIZE_FRAME*2);


size_crnt = 1;
i = 1;
w = hanning(SIZE_FRAME*2);
while size_crnt < size_total- SIZE_FRAME
    %% Framewise windowing
    s_frame = s(size_crnt:size_crnt-1 + SIZE_FRAME);
    s_frame_LP =  w.* [s_frame_1d ; s_frame];

    %% Residual extraction
    LP = lpc(s_frame_LP,LPorder);
    LP_1d = lpc(s_frame_LP_1d,LPorder);
    res = filter(LP,1,s_frame_LP);
    mod_res = filter(LP_1d,1,s_frame_LP);

    if i > 1 %1d buffer is filled
        dres = res - mod_res;
    else     %1d buffer is empty
        dres = res;
    end

    dres_bp = dres;
    dres_bp = abs(dres_bp);
    dres_bp_mid = dres_bp_1d(SIZE_FSHIFT+1:SIZE_FRAME*2) + dres_bp(1:SIZE_FSHIFT);


    %% Noise area detection using mean thresholding
    max_val = max(dres_bp_mid);
    if max_val > mean(dres_bp_mid) * MEAN_thr;
        n_flag = 1;
    else
        n_flag = 0;
    end

    %% Noise region reconstruction
    if prm.BYPASS == 1
        n_flag = 0;
    end

    if prm.BYPASS_INV == 1
        n_flag = 1;
    end


    %% Frame Re-synthesis
    S_in = mdct([s_frame_2d;s_frame_1d]);
    if n_flag == 1 || n_flag_prv == 1
        %Magnitude reconstruction
        S_in(binL:binH) = S_in_1d(binL:binH) .* RAND_TABLE(binL:binH);

        if prm.DETECT == 1
            S_in(binL:binH) = S_in((binL:binH),1).*0;
        end
    end

    if prm.TONE_REMOVE == 1
        %% remove tonal noise using notch filter
        if n_flag == 1 || (notch_cnt > 0 && notch_cnt <= TONE_len)
            S_in(binL_notch1:binH_notch1) =  S_in_1d(binL_notch1:binH_notch1)  .* RAND_TABLE(binL_notch1:binH_notch1);

            notch_cnt = notch_cnt+1;
        end

        if notch_cnt > TONE_len
            notch_cnt = 0;
        end
    end

    s_proc = imdct(S_in);


    %% DRES write option
    if prm.DRES_OUT == 1
        s_proc = dres_bp;
    end

    s_out(size_crnt : size_crnt-1 + SIZE_FRAME*2) = s_out(size_crnt : size_crnt-1 + SIZE_FRAME*2) + s_proc;


    %% Proccessed signal buffering
    s_frame_2d = s_frame_1d;
    s_frame_1d = s_frame;
    s_frame_LP_1d = s_frame_LP;
    dres_bp_1d = dres_bp;    
    S_in_1d = S_in;
    n_flag_prv = n_flag;

    size_crnt = size_crnt + SIZE_FSHIFT;
    i = i+1;
    RAND_TABLE_shift = RAND_TABLE(1);
    RAND_TABLE(1:SIZE_FRAME-1) = RAND_TABLE(2:SIZE_FRAME);
    RAND_TABLE(SIZE_FRAME) = RAND_TABLE_shift;
end

wavwrite(s_out./32767, FS, 16, output);

% plot(s);
% hold on;
% plot(s_out(SIZE_FSHIFT:length(s_out))*100,'r');

end