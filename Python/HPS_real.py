import numpy as np
import sounddevice as sd
from collections import deque

# Taajuusresoluutio = sample_rate / window_length eli noin 1Hz välein 
samp = 48000  # Näytteenottotaajuus
windowlen = 4096 *16  # Ikkunan pituus (näytteitä)

###################################################################
# Reaaliaikainen f0-estimointi: yksi kehys kerrallaan
###################################################################

def HPS_f0_frame(frame, sample_rate = samp, window_length=windowlen, partials=5):

    freqs = np.fft.rfftfreq(window_length, 1/sample_rate)
    # Otetaan huomioon vain 50 Hz - 1000 Hz alue
    minf = 50
    maxf = 1000

    # Pad frame if needed
    if len(frame) < window_length:
        frame = np.pad(frame, (0, window_length - len(frame)))
    else:
        frame = frame[:window_length]

    # Ikkunoidaan kehys
    windowed_frame = frame * np.hanning(window_length)
    
    # Lasketaan magnitudispektri 
    mag_spec = np.abs(np.fft.rfft(windowed_frame))
    # Tallennetaan alkuperäinen spektri muistiin
    hps_spec = mag_spec.copy()
    
    # Toteutetaan itse HPS-algoritmi
    for p in range(2, partials+1):
        downsampled = mag_spec[::p]
        hps_spec = hps_spec[:len(downsampled)] * downsampled
    
    # Etsitään huiput -> löydetään perustaajuusestimaatti
    peak_idx = np.argmax(hps_spec)
    f0 = freqs[peak_idx]
        
    if f0 > 130:
        target = f0 / 2
        lower_idx = np.argmin(np.abs(freqs - target))

        amp_main  = mag_spec[peak_idx]
        amp_lower = mag_spec[lower_idx]
        if amp_lower > 0.2 * amp_main:
            f0 = freqs[lower_idx]

    return f0

# Jos haluaa smoothingin, voi käyttää alla olevaa koodia (myös audio_callbackin sisällä)

f0_values = deque(maxlen=20)  # Keep last 20 measurements

def smooth_f0(f0):
    # Lisää uusi arvo historiaan
    f0_values.append(f0)

    # Tarvitaan vähintään 3 arvoa
    if len(f0_values) < 3:
        return f0 
    
    # Palauta mediaani kaikista arvoista
    smoothed_f0 = np.median(f0_values)
    return smoothed_f0


def audio_callback(indata, frames, time, status):
    
    # Muunnetaan monoksi, jos stereo
    audio_data = indata[:, 0] if indata.ndim > 1 else indata
    
    # Lasketaan dB-taso
    db_level = 20 * np.log10(np.sqrt(np.mean(audio_data**2)))
    threshold = -30  # dB-taso, jonka alapuolella ei lasketa f0:aa
    
    # Lasketaan f0 vain, jos äänenvoimakkuus on riittävä
    if db_level > threshold:
        f0_raw = HPS_f0_frame(audio_data.flatten(), sample_rate=samp)
        f0_smoothed = smooth_f0(f0_raw)  # Smoothataan
        
        print(f"F0: {f0_smoothed:.2f} Hz | Raw: {f0_raw:.2f} Hz | dB: {db_level:.1f}", end='\r')
    else:
        f0_values.clear()  # Clear history when silent
        print(f"dB: {db_level:.1f} (too quiet)       ", end='\r')

# Aloitetaan äänitys
try:
    with sd.InputStream(callback=audio_callback, 
                        channels=1, # Mono-kanava
                        samplerate=48000, # Mikrofonin näytteenottotaajuus
                        blocksize=4096): # Näyte 85 ms välein (4096/44100)
        sd.sleep(100000)  # Pyöritä ohjelmaa 100 sekuntia
except KeyboardInterrupt:
    print("\n\n✓ Stopped")
