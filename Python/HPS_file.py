import numpy as np
import librosa as lr
import os 

##################################################################
# Äänen lataus
# Use absolute path based on script location
script_dir = os.path.dirname(os.path.abspath(__file__))
audio_path = os.path.join(script_dir, 'guitar_D.wav')

audio, fs = lr.load(audio_path, sr=None)

def HPS_f0(audio_samples, sample_rate, window_length=4096,
            hop_length=1024, window=np.hanning, partials=5):

    f0s = []
    freqs = np.fft.rfftfreq(window_length, 1/sample_rate)
    # Otetaan huomioon vain 50 Hz - 1000 Hz alue
    minf = 50
    maxf = 1000
    # Muunnetaan taajuudet indekseiksi
    minf_idx = np.searchsorted(freqs, minf)
    maxf_idx = np.searchsorted(freqs, maxf)

    for i in range(0, len(audio_samples)-window_length, hop_length):
        # Otetaan kehys ja ikkunoidaan se
        frame = audio_samples[i:i+window_length] * window(window_length)
        frame = frame * window(window_length)

        # Lasketaan magnitudispektri
        mag_spec = np.abs(np.fft.rfft(frame))
        # Leikataan haluttuun taajuusalueeseen
        mag_spec = mag_spec[minf_idx:maxf_idx]
        # Tallennetaan alkuperäinen spektri muistiin
        hps_spec = mag_spec.copy()

        # Lasketaan periodic correlation array
        # http://musicweb.ucsd.edu/~trsmyth/analysis/Harmonic_Product_Spectrum.html
        for p in range(1, partials+1):
            downsampled = mag_spec[::p]
            hps_spec = hps_spec[:len(downsampled)] * downsampled

        # Etsitään huippu -> löydetään perustaajuusestimaatti
        peak_idx = np.argmax(hps_spec)
        f0 = freqs[minf_idx + peak_idx]
        f0s.append(f0)

    return f0s


# Testataan funktiota
f0s = HPS_f0(audio[fs:2*fs], fs)
print(f0s)
print(f"Number of frames analyzed: {len(f0s)}")
print(f"Minimum f0: {np.min(f0s):.2f} Hz")
print(f"Maximum f0: {np.max(f0s):.2f} Hz")
print(f"Mean f0: {np.mean(f0s):.2f} Hz")
print(f"Median f0: {np.median(f0s):.2f} Hz")
print(f"\nFirst 10 values: {f0s[:10]}")