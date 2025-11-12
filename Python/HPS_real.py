import numpy as np
import sounddevice as sd

# Taajuusresoluutio = sample_rate / window_length eli noin 3Hz välein 
samp = 44100  # Näytteenottotaajuus
windowlen = 4096 * 4  # Ikkunan pituus (näytteitä)

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
    
    return f0

# Jos haluaa smoothingin, voi käyttää alla olevaa koodia (myös audio_callbackin sisällä)
'''from collections import deque
f0_history = deque(maxlen=5)  # Keep last 5 measurements'''


def audio_callback(indata, frames, time, status):
    
    # Muunnetaan monoksi, jos stereo
    audio_data = indata[:, 0] if indata.ndim > 1 else indata

    # Lasketaan dB-taso
    db_level = 20 * np.log10(np.sqrt(np.mean(audio_data**2)))
    
    # Process with HPS
    if db_level > -30:  # Threshold to avoid noise
        f0 = HPS_f0_frame(audio_data.flatten(), sample_rate=44100)
        print(f"F0: {f0:.2f} Hz | dB: {db_level:.1f}", end='\r')
'''
        # Add to history for smoothing
        f0_history.append(f0)
        
        # Calculate median of recent values (more stable than mean)
        if len(f0_history) >= 3:
            smoothed_f0 = np.median(f0_history)
            print(f"F0: {smoothed_f0:.2f} Hz | Raw: {f0:.2f} Hz | dB: {db_level:.1f}", end='\r')
        else:
            print(f"F0: {f0:.2f} Hz | dB: {db_level:.1f}", end='\r')
    else:
        # Clear history when silent
        f0_history.clear()
        print(f"dB: {db_level:.1f} (too quiet)       ", end='\r')'''

# Aloitetaan äänitys
try:
    with sd.InputStream(callback=audio_callback, 
                        channels=1, # Mono-kanava
                        samplerate=44100, # Mikrofonin näytteenottotaajuus
                        blocksize=4096): # Näyte 85 ms välein (4096/44100)
        sd.sleep(100000)  # Pyöritä ohjelmaa 100 sekuntia
except KeyboardInterrupt:
    print("\n\n✓ Stopped")
