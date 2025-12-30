% AUDIO RECORDING + TIME & FREQUENCY DOMAIN PLOTS

Fs = 48000; Channels = 1; bits = 16;
r = audiorecorder(Fs, bits, Channels);
duration = 5; disp('Recording Started');
recordblocking(r, duration);
disp('Recording Stopped');

x = getaudiodata(r);
sound(x, Fs);
t = 0:1/Fs:(length(x)-1)/Fs;
subplot(2, 1, 1); plot(t, x, 'LineWidth', 1.5);
xlabel('time[s]'); ylabel('Amplitude');
title('Time Domain Plot of recorded signal');
n = length(x); F = 0:(n-1)*Fs/n;
y = fft(x, n);
F_0 = (-n/2:n/2-1).*(Fs/n);
y_0 = fftshift(y);
ay_0 = abs(y_0);
subplot(2, 1, 2); plot(F_0, ay_0, 'LineWidth', 1.5);
xlabel('Frequency [Hz]'); ylabel('Amplitude');
title('Frequency domain plot of audio signal');
filename = 'recordingAudio.wav';
audiowrite(filename, x, Fs);

