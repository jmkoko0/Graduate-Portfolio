% PITCH DETECTION AND RELATIVE CHORD GENERATION

% Record
fs = 48000;
recObj = audiorecorder(fs, 16, 1);
disp('Start playing...');
recordblocking(recObj, 10);
disp('Done.');
y = getaudiodata(recObj);

% Root note list (MIDI numbers for C = 0)
rootNames = {'C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'};
rootChoice = menu('Select a root note:', rootNames);

% Major or minor
scaleChoice = menu('Select scale type:', {'Major','Minor'});

% Build scale intervals
if scaleChoice == 1
    intervals = [0 2 4 5 7 9 11]; % Major scale (ionian)
else
    intervals = [0 2 3 5 7 8 10]; % Natural minor (aeolian)
end

% Generate full MIDI set for that scale across octaves
rootMidi = rootChoice - 1; % 0 for C, 1 for C#, etc.
scale_midi = [];
for octave = 0:10
    scale_midi = [scale_midi, rootMidi + intervals + 12*octave];
end
scale_midi = sort(scale_midi); % Ensure sorted

function qnote = quantizeToScaleDown(note, scale_midi)
    % Round DOWN to nearest diatonic note
    if isnan(note)
        qnote = NaN;
        return;
    end
    
    % Find scale notes less than or equal to the detected note
    lower_notes = scale_midi(scale_midi <= note);
    
    if isempty(lower_notes)
        % If no lower notes, use the lowest scale note
        qnote = scale_midi(1);
    else
        % Use the highest note that's lower than or equal to detected note
        qnote = lower_notes(end);
    end
end

function hnote = shiftScale(note, scale_midi, steps)
    % Find the index of note in scale_midi
    idx = find(scale_midi == note, 1);
    if isempty(idx)
        hnote = note; % fail-safe
    else
        newIdx = idx + steps;
        if newIdx < 1
            newIdx = 1;
        elseif newIdx > length(scale_midi)
            newIdx = length(scale_midi);
        end
        hnote = scale_midi(newIdx);
    end
end

% Pitch detection parameters
frameLen = round(0.03*fs);  % 30ms frames
hopLen   = round(0.01*fs);   % 10ms hop (20ms overlap)

[f0, t] = pitch(y, fs, ...
    'Method','SRH', ...
    'Range',[80 1000], ...
    'WindowLength', frameLen, ...
    'OverlapLength', frameLen - hopLen);

% Energy-based voice activity detection
energy = buffer(y.^2, frameLen, frameLen-hopLen, 'nodelay');
energy = mean(energy, 1);
energy = energy(:);

energyThresh = 0.01 * max(energy);   % 1% of max energy
voiced = energy > energyThresh;

% Remove unvoiced frames and median filtering
f0(~voiced) = NaN;
f0 = medfilt1(f0, 5, 'omitnan', 'truncate');

midi_est = 69 + 12*log2(f0/440);
midi_est = round(midi_est);

figure;
plot(midi_est)
title('Detected MIDI Pitch Over Time')
ylabel('MIDI Note')
xlabel('Frame')

% Quantize DOWN to nearest diatonic note
quantized_midi = arrayfun(@(n) quantizeToScaleDown(n, scale_midi), midi_est);

figure;
plot(midi_est, 'b'); hold on;
plot(quantized_midi, 'r');
legend('Detected','Quantized (Down)');
title('Pitch Quantization to Selected Key');
xlabel('Frame');
ylabel('MIDI Note');

% Generate harmony notes (3rd and 5th)
harmony_3rd = zeros(size(quantized_midi));
harmony_5th = zeros(size(quantized_midi));

for i = 1:length(quantized_midi)
    note = quantized_midi(i);
    
    if ~isnan(note)
        harmony_3rd(i) = shiftScale(note, scale_midi, 2);  % 2 steps up for 3rd
        harmony_5th(i) = shiftScale(note, scale_midi, 4);  % 4 steps up for 5th
    else
        harmony_3rd(i) = NaN;
        harmony_5th(i) = NaN;
    end
end

figure;
plot(quantized_midi, 'r', 'LineWidth', 1.5); hold on;
plot(harmony_3rd, 'g', 'LineWidth', 1.5);
plot(harmony_5th, 'b', 'LineWidth', 1.5);
legend('Root (Quantized)', '3rd', '5th');
title('Harmonization of Detected Pitch');
xlabel('Frame');
ylabel('MIDI Note');
grid on;

% Generate harmonized audio using dynamic pitch shifting
disp('Generating harmonized audio...');

% Use a segmented approach: process larger chunks based on stable pitch regions
harmony_3rd_audio = zeros(size(y));
harmony_5th_audio = zeros(size(y));
corrected_root_audio = zeros(size(y));  % For the corrected root note

% Find regions of stable pitch (using QUANTIZED pitch, not detected)
numFrames = length(quantized_midi);
segments = [];
currentNote = NaN;
currentDetected = NaN;
segStart = 1;

for i = 1:numFrames
    if ~isnan(quantized_midi(i))
        if isnan(currentNote) || quantized_midi(i) ~= currentNote
            % New note detected
            if ~isnan(currentNote)
                % Save previous segment with both quantized and detected pitch
                segEnd = (i-1) * hopLen + frameLen;
                segments = [segments; segStart, min(segEnd, length(y)), currentNote, currentDetected];
            end
            currentNote = quantized_midi(i);
            currentDetected = median(midi_est(max(1,i-2):min(numFrames,i+2)), 'omitnan');
            segStart = (i-1) * hopLen + 1;
        end
    else
        % Silence/unvoiced
        if ~isnan(currentNote)
            % End current segment
            segEnd = (i-1) * hopLen + frameLen;
            segments = [segments; segStart, min(segEnd, length(y)), currentNote, currentDetected];
            currentNote = NaN;
            currentDetected = NaN;
        end
    end
end

% Add final segment
if ~isnan(currentNote)
    segments = [segments; segStart, length(y), currentNote, currentDetected];
end

% Process each segment
disp(['Processing ' num2str(size(segments, 1)) ' pitch segments...']);

for s = 1:size(segments, 1)
    segStart = segments(s, 1);
    segEnd = segments(s, 2);
    quantized_note = segments(s, 3);  % This is the QUANTIZED (rounded down) note
    detected_note = segments(s, 4);   % This is the DETECTED note
    
    % Calculate how much to correct the original audio
    root_correction = quantized_note - detected_note;
    
    % Find the harmony notes for this QUANTIZED pitch
    harm3 = shiftScale(quantized_note, scale_midi, 2);
    harm5 = shiftScale(quantized_note, scale_midi, 4);
    
    % Calculate shifts relative to the DETECTED note (not quantized)
    % This way all three voices are shifted from the original audio
    shift_root = root_correction;
    shift_3rd = harm3 - detected_note;
    shift_5th = harm5 - detected_note;
    
    % Extract segment
    segment = y(segStart:segEnd);
    
    % Apply pitch shifts to this segment
    if length(segment) > 100  % Only process if segment is long enough
        % Limit pitch shifts to avoid shiftPitch errors (max ±12 semitones per call)
        % If larger shifts needed, apply in multiple steps
        seg_root = applyPitchShiftSafe(segment, shift_root);
        seg_3rd = applyPitchShiftSafe(segment, shift_3rd);
        seg_5th = applyPitchShiftSafe(segment, shift_5th);
        
        % Create crossfade windows for smooth transitions
        crossfade_len = min(200, floor(length(segment)/4)); % 200 samples or 25% of segment
        fade_in = linspace(0, 1, crossfade_len)';
        fade_out = linspace(1, 0, crossfade_len)';
        
        % Apply fade-in at start of segment (except first segment)
        if s > 1 && length(seg_root) >= crossfade_len
            seg_root(1:crossfade_len) = seg_root(1:crossfade_len) .* fade_in;
            seg_3rd(1:crossfade_len) = seg_3rd(1:crossfade_len) .* fade_in;
            seg_5th(1:crossfade_len) = seg_5th(1:crossfade_len) .* fade_in;
        end
        
        % Apply fade-out at end of segment (except last segment)
        if s < size(segments, 1) && length(seg_root) >= crossfade_len
            seg_root(end-crossfade_len+1:end) = seg_root(end-crossfade_len+1:end) .* fade_out;
            seg_3rd(end-crossfade_len+1:end) = seg_3rd(end-crossfade_len+1:end) .* fade_out;
            seg_5th(end-crossfade_len+1:end) = seg_5th(end-crossfade_len+1:end) .* fade_out;
        end
        
        % Place shifted segments back (handle length differences)
        len_root = min(length(seg_root), segEnd - segStart + 1);
        len_3rd = min(length(seg_3rd), segEnd - segStart + 1);
        len_5th = min(length(seg_5th), segEnd - segStart + 1);
        
        corrected_root_audio(segStart:segStart+len_root-1) = corrected_root_audio(segStart:segStart+len_root-1) + seg_root(1:len_root);
        harmony_3rd_audio(segStart:segStart+len_3rd-1) = harmony_3rd_audio(segStart:segStart+len_3rd-1) + seg_3rd(1:len_3rd);
        harmony_5th_audio(segStart:segStart+len_5th-1) = harmony_5th_audio(segStart:segStart+len_5th-1) + seg_5th(1:len_5th);
    end
    
    % Show note names for debugging
    noteNames = {'C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'};
    detected_name = noteNames{mod(round(detected_note), 12) + 1};
    quantized_name = noteNames{mod(quantized_note, 12) + 1};
    harm3_name = noteNames{mod(harm3, 12) + 1};
    harm5_name = noteNames{mod(harm5, 12) + 1};
    
    fprintf('Segment %d/%d: Played %s → Corrected to %s → Harmonies: %s + %s\n', ...
        s, size(segments,1), detected_name, quantized_name, harm3_name, harm5_name);
end

disp('Harmonization complete!');

% Combine corrected root with harmonies
harmonized_audio = corrected_root_audio + 0.4*harmony_3rd_audio + 0.4*harmony_5th_audio;

% Normalize to prevent clipping
max_val = max(abs(harmonized_audio));
if max_val > 0
    harmonized_audio = 0.95 * harmonized_audio / max_val;
end

% Normalize individual tracks
if max(abs(harmony_3rd_audio)) > 0
    harmony_3rd_audio = harmony_3rd_audio / max(abs(harmony_3rd_audio));
end
if max(abs(harmony_5th_audio)) > 0
    harmony_5th_audio = harmony_5th_audio / max(abs(harmony_5th_audio));
end

% Write outputs
audiowrite('harmonized_output.wav', harmonized_audio, fs);
audiowrite('original.wav', y, fs);
audiowrite('corrected_root.wav', corrected_root_audio, fs);
audiowrite('harmony_3rd.wav', harmony_3rd_audio, fs);
audiowrite('harmony_5th.wav', harmony_5th_audio, fs);

disp('Audio files written:');
disp('  - harmonized_output.wav (corrected root + 3rd + 5th)');
disp('  - original.wav (what you played)');
disp('  - corrected_root.wav (quantized to scale)');
disp('  - harmony_3rd.wav');
disp('  - harmony_5th.wav');

function shifted = applyPitchShiftSafe(segment, semitones)
    % Safely apply pitch shift, handling large shifts by breaking into steps
    % shiftPitch has limitations on max shift based on segment length
    
    if abs(semitones) < 0.01
        shifted = segment;
        return;
    end
    
    % Calculate max safe shift based on segment length
    % shiftPitch requires: shift < -12*log2(overlapLength/windowLength)
    % For typical settings, this limits to about ±10-12 semitones
    max_shift = 10;
    
    if abs(semitones) <= max_shift
        % Direct shift
        try
            shifted = shiftPitch(segment, semitones);
        catch
            % If still fails, use simple resampling fallback
            shift_factor = 2^(semitones / 12);
            shifted = resample(segment, round(length(segment) * shift_factor), length(segment));
            if length(shifted) > length(segment)
                shifted = shifted(1:length(segment));
            elseif length(shifted) < length(segment)
                shifted = [shifted; zeros(length(segment) - length(shifted), 1)];
            end
        end
    else
        % Break large shift into smaller steps
        num_steps = ceil(abs(semitones) / max_shift);
        step_size = semitones / num_steps;
        shifted = segment;
        
        for i = 1:num_steps
            try
                shifted = shiftPitch(shifted, step_size);
            catch
                % Fallback to resampling
                shift_factor = 2^(step_size / 12);
                shifted = resample(shifted, round(length(shifted) * shift_factor), length(shifted));
            end
        end
        
        % Adjust length to match original
        if length(shifted) > length(segment)
            shifted = shifted(1:length(segment));
        elseif length(shifted) < length(segment)
            shifted = [shifted; zeros(length(segment) - length(shifted), 1)];
        end
    end
end