%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% IEEE 802.11n/ac simulation on the Rician channel.
%
% Copyright (C) 2022  Shiyue He (hsy1995313@gmail.com)
% 
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear; 
close all;

%% Variables
global MCS_TAB 
global N_CP N_LTF N_FFT N_LTFN N_TAIL
global SCREAMBLE_POLYNOMIAL SCREAMBLE_INIT
global MIN_BITS

MHz         = 1e6;          % 1MHz
Hz          = 1;

Nbits       = 8192;
MCSi        = 8;

NO_CHANNEL = true;

%% Channel model
BW          = 20;                   % Bandwidth (20 MHz)
doppler     = 500 * Hz;             % Doppler shift is around 5 Hz
path_delays = [0, 0.05, 0.1] / MHz;
avg_gains   = [0, -20, -40];        % Average path gain in dB

rician = comm.RicianChannel(...
        'SampleRate', BW * MHz,...
        'PathDelays', path_delays,...
        'AveragePathGains', avg_gains,...
        'NormalizePathGains', true,...
        'DirectPathDopplerShift', doppler,...
        'PathGainsOutputPort', true);

%% Transmitter
TxBits = randi(2, [Nbits, 1]) -1;

Npad = MIN_BITS - mod(size(TxBits, 1) + N_TAIL, MIN_BITS);
TxPadBits = [TxBits; zeros(Npad + N_TAIL, 1)];

IEEE80211_scrambler = comm.Scrambler( ...
                        'CalculationBase', 2, ...
                        'Polynomial', SCREAMBLE_POLYNOMIAL, ...
                        'InitialConditions', SCREAMBLE_INIT ...
                        );
TxScrambledBits = IEEE80211_scrambler(TxPadBits);

TxEncodedBits = IEEE80211ac_ConvolutionalEncoder(TxScrambledBits, MCS_TAB.rate(MCSi));

TxModData = qammod(TxEncodedBits, MCS_TAB.mod(MCSi), 'InputType', 'bit', 'UnitAveragePower',true);
Payload_t = IEEE80211ac_Modulator(TxModData);

[STF, LTF, DLTF] = IEEE80211ac_PreambleGenerator(1);

TxFrame = [STF; LTF; DLTF; Payload_t];

%% Channel model
if NO_CHANNEL
    RxFrame = TxFrame;
else
    RxFrame = rician(TxFrame);
end

%% Receiver
[sync_results, LTF_index] = OFDM_SymbolSync(RxFrame, LTF(2*N_CP +1: end, 1));

if LTF_index == N_LTF * 2   % If sync is correct
    
    RxLTF = RxFrame(LTF_index - N_LTF +1: LTF_index);
    RxDLTF = RxFrame(LTF_index +1: LTF_index + (N_CP + N_FFT) * N_LTFN);
    RxPayload_t = RxFrame(LTF_index + (N_CP + N_FFT) * N_LTFN +1: end);

    CSI = IEEE80211ac_ChannelEstimator(RxDLTF, 1, 1);

    RxPayload_f = IEEE80211ac_Demodulator(RxPayload_t, CSI);

    DecodedBits = qamdemod(RxPayload_f, MCS_TAB.mod(MCSi), 'OutputType', 'bit', 'UnitAveragePower',true);

    DescrambledBits = IEEE80211ac_ConvolutionalDecoder(DecodedBits, MCS_TAB.rate(MCSi));

    IEEE80211_descrambler = comm.Descrambler( ...
                        'CalculationBase', 2, ...
                        'Polynomial', SCREAMBLE_POLYNOMIAL, ...
                        'InitialConditions', SCREAMBLE_INIT ...
                        );
    RxPadBits = IEEE80211_descrambler(DescrambledBits);

    RxBits = RxPadBits(1: end - N_TAIL - Npad);
end

%% Transmission result
figure;
plot(abs(sync_results));
title('Correlation result');

if LTF_index == N_LTF * 2
    
    error_bits = xor(RxBits, TxBits);
    BER = sum(error_bits) / Nbits;

    figure; hold on; 
    plot(abs(RxLTF(N_CP *2 +1: N_CP *2 + N_FFT)));
    plot(abs(RxLTF(N_CP *2 + N_FFT +1: end)));
    title('Long preamble in the time domain');

    figure;
    subplot(211);
    plot(abs(CSI));
    title('CSI estimation abs');
    subplot(212);
    plot(angle(CSI));
    title('CSI estimation angle');

    figure; hold on;
    scatter(real(RxPayload_f), imag(RxPayload_f));
    title('Constellation of RX payload');

    clc;
    disp(['*********Rician Channel Model********']);
    disp(['    Path delays: [' num2str(path_delays) '] s']);
    disp(['    Path Gains: [' num2str(avg_gains) '] dB']);
    disp(['    Maximum Doppler shift: ' num2str(doppler) ' Hz']);
    disp(['*********Transmission Result*********']);
    disp(['    Packet length: ' num2str(length(RxFrame) / BW) ' us']);
    disp(['    Time synchronization successful!']);
    if BER == 0
        disp(['    Frame reception successful!']);
    else
        disp(['    Frame reception failed!']);
        disp(['    BER: ' num2str(BER)]);
    end
    
    figure;
    stem(error_bits);
    title('Error bits');
    
else
    clc;
    disp(['*************************************']);
    disp(['    Time synchronization error !']);
end
disp(['*************************************']);