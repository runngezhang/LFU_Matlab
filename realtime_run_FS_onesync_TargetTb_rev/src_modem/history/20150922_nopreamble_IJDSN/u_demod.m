function u_demod(fname_rcv, fname_txt, bit_name_txt, preamble_rcv, Tb, p)

addpath('src_modem/src');
load('src/BPF_19500_20500.mat');

MIC_ON = 0;
INTERLEAVE = p.INTERLEAVE;
BC_GOLAY = p.BC_GOLAY;
Fs = p.fs;
SCALE_MAX = p.SCALE_MAX;

%Parameters for Golay coding
M = 2; %2 x 12 bit
N = 3; %3 x 8 bit
B = 8; %Unit symbol length
C = 12; %Unit code length
G = 23; %Unit golay code length

    
if BC_GOLAY
    G = G;
else
    G = C;
end

header_bits = [1 1 1 0 0 1 1 0];
ender_bits = [1 1 1 1 1 1 1 0];
bit_buff = zeros(1, M*G);

s_prv = zeros(1, Tb);
s_BPF_tail_prv = zeros(1, length(BPF)-1);
header_flag = 0;
err_cnt_char = 0;
bit_cnt = 0;

fin = fopen(fname_rcv, 'rb');
fout = fopen(fname_txt, 'wt');
fbit = fopen(bit_name_txt, 'wt');
% fbit_bc = fopen(['src_modem/bit/bit_bc_rcv.txt'], 'wt');

% fdebug1 = fopen('snd/snd_golay_RT_BP.pcm', 'wb');
% fdebug2 = fopen('snd/snd_golay_RT_demod_BP.pcm', 'wb');


if MIC_ON
    %Initialize Audio recording
    [obj]=dsp_record(0, Fs, 1, Tb, 'start');
end



% Discard wav header 
fread(fin, 22, 'int16');

nFrmIdx = 0;
while (1)
    if MIC_ON
        [obj, s]=dsp_record(obj, Fs, 1, Tb, 'record');
        s = s .* 32767;
        s = s';
        len = length(s);
    else
        %File-based processing
        [s, len] = fread(fin, Tb, 'int16');
        s = s';
    end
    
    %Check Ultrasonic band's average power
    if len ~= Tb
        break;
    else
        if p.dec_BPF
            s_BPF = conv(s,BPF);
            s_BPF(1:length(s_BPF_tail_prv)) = s_BPF(1:length(s_BPF_tail_prv)) + s_BPF_tail_prv;
            s_BPF_tail = s_BPF(length(s)+1:length(s_BPF));
            
            s_BPF = s_BPF(1:length(s));
            
            s = s_BPF;
        end
    end
    
% %     S = fft(s, Tb);
% %     bin_B = p.fs / Tb;
% %     B_idx = floor(20000 / bin_B);
% %     tmp = S(B_idx-1:B_idx+1);
% %     S = zeros(1,Tb/2);
% %     S(B_idx-1:B_idx+1) = tmp;
% %     S_proc = [0, S, flipud(S(1:end-1)')'];
% %     s = real(ifft(S_proc, Tb));


    bit = bit_detect(s_prv, s);
    
%     if bit == 1
%         fprintf(fbit, '%c', '1');
%     else
%         fprintf(fbit, '%c', '0');
%     end
    
    %Stack bits
    bit_buff(1:M*G-1) = bit_buff(2:M*G);
    bit_buff(M*G) = bit;
    bit_cnt = bit_cnt + 1;
    
    if header_flag == 0 || (header_flag == 1 && bit_cnt == M*G)
        %Pefrom channel decoding
        bit_blk_ibc = matB2C(bit_buff, M, G);
        
        if INTERLEAVE
            bit_blk_ibc = [bit_blk_ibc'; [0, 0] ]'; %Zero padding
            bit_blk_bc = matdeintrlv(bit_blk_ibc',12,2);
            bit_blk_bc = bit_blk_bc';
            bit_blk_bc = bit_blk_bc(:,1:23);
        else
            bit_blk_bc = bit_blk_ibc;
        end
        
        
        if BC_GOLAY
            bit_blk_c = golaycodec(bit_blk_bc);
        else
            bit_blk_c = bit_blk_bc;
        end
        bit_blk = matB2C(bit_blk_c, N, B);        
        bit_cnt = 0;

        
        if header_flag
            bit_write(bit_blk, fbit);
            for k = 1 : N
                if mod(sum(bit_blk(k,:)),2)==0;
                    c = char(bi2de(bit_blk(k,1:7)));
                    fprintf(fout, '%c', c);
                    %                         disp(sprintf('%c', c));

                    %                         url_buff(url_cnt) = c;
                    %                         url_cnt = url_cnt + 1;
                    %                         if c == 10; %New line, LF
                    %                            URL = char(url_buff(1:url_cnt));
                    % %                            web(URL', '-new', '-notoolbar');
                    %                            url_buff = zeros(40,1);
                    %                            url_cnt = 1;
                    %                         end
                else
                    %                         disp('error detected!');
                    err_cnt_char = err_cnt_char + 1;
                end
            end
        end
        
        %Sync set
        if isequal(header_bits, bit_blk(1,:)) && isequal(header_bits, bit_blk(2,:))&& isequal(header_bits, bit_blk(3,:))
            header_flag = 1;
        end
        
        %Finish decoding
        if header_flag && isequal(ender_bits, bit_blk(3,:))
            break;
        end
    end
    
    s_prv = s;
    if p.dec_BPF
        s_BPF_tail_prv = s_BPF_tail;
    end
    nFrmIdx = nFrmIdx + 1;
    
%     %Write preprocessed waveform
%     fwrite (fdebug1, s_org, 'int16');
%     fwrite (fdebug2, s_BPF, 'int16');
end
fclose('all');

end