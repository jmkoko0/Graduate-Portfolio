This MATLAB code takes an 10-second audio recording from the user (intended to be a single-pitched instrument like a trumpet or clarinet) and generates a harmonized audio file. 

After recording, the user then selects a note to base the harmonization off of then the respective major/minor scale. The recording is then analyzed and each detected pitch is quantized to a MIDI value. The harmonization is then applied giving a 3rd and 5th relative to the chosen scale. 
Plots are generated of (1) the detected quantized pitches in MIDI value, (2) any corrected pitches to account for non-diatonic notes played by the user (i.e. if the user plays a concert B but picks a Bb major scale), and (3) the harmonized MIDI values on top of the original corrected plot. The corrected pitches always "round down" to the nearest diatonic pitch. 

The code generates 5 audio files:
original.wav - The original unprocessed recording
corrected_root.wav - The original audio with pitch corrections applied to non-diatonic notes
harmony_3rd.wav - ONLY the major/minor 3rd above the original audio
harmony_5th.wav - ONLY the 5th above the original audio
harmonized_output.wav - The full harmonized audio with the original corrected, 3rd, and 5th audio files together. 

The audio files provided contain harmonized audio based off of me playing a concert Bb major scale on the clarinet with the Bb major scale as the base for the harmonization. The chords generated follow the exact structure that triads of a major scale follow: I - ii - iii - IV - V - vi - vii dim 

Several elements were included to fix errors involving playback and the audible harmonization. There is a block of code that eliminates harmonization of audio that isn't part of the actual instrument (i.e. background/white noise). This can be shown in the plots, where the MIDI assignments do not appear until an audible pitch from the instrument can be detected. The harmonization is done by segments of pitches instead of frame-by-frame analysis, since the shiftPitch function works better on drawn out segments instead of tiny frames. This allowed for the harmonization to be much more stable and avoidant of pops and false detections. 

You will notice that the harmonized audio file still contains some pops and clicks. I tested the code out with different instruments both acoustic and digital and came to the conclusion that the harmonization reacts differently to different instruments but the general harmonization works. The lower register on clarinet in particular was detected as an octave above what was played due to the overtone nature of the instrument. The same octave scale played on the trumpet was perfectly detected. This is an element I will continue to work out and troubleshoot.