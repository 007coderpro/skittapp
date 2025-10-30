import os, sys
import numpy as np
from scipy import signal
import matplotlib.pyplot as plt
import IPython.display as ipd
import librosa.display
import soundfile as sf
import libfmp.b

%matplotlib inline

##################################################################
# Tänne rakennetaan HPS signaalin käsittely menetelmä
# Jos tarvii inspistä niin step-by-step quide -> 
# https://www.audiolabs-erlangen.de/resources/MIR/FMP/C8/C8S1_HPS.html
##################################################################

# Äänen vastaanoton alustus
"""
Tähän voi tehdä signaalin alustus jutut eli määritellä vain seuraavat.
x (np.array): Input signal
filter_len (int): Filterin pituus

???
"""



##################################################################
# Apu funktioiden luominen
##################################################################

# Horisonttaalinen filtteri
def median_filterH(x, filter_len):
    """
    x (np.array): Input matrix
    filter_len (Int): Filter_pituus
    """
    return signal.medfilt(x, [1, filter_len])

# Vertikaali filtteri
def median_filterV(x, filter_len):
    """
    x (np.array): Input matrix
    filter_len (Int): Filter_pituus
    """
    return signal.medfilt(x, [filter_len, 1])


##################################################################
# HPS-analyysi (Harmonic-Percussive Separation)
##################################################################



##################################################################
# Ihan vain koska plotit on kivoja :)
##################################################################

# Laskee Y, jotta voidaan piirtää
def compute_plot_spectrogram(x, Fs=22050, N=4096, H=2048, ylim=None,
                     figsize =(5, 2), title='', log=False):
    N, H = 1024, 512
    X = librosa.stft(x, n_fft=N, hop_length=H, win_length=N, window='hann', 
                     center=True, pad_mode='constant')
    Y = np.abs(X)**2
    if log:
        Y_plot = np.log(1 + 100 * Y)
    else:
        Y_plot = Y
    libfmp.b.plot_matrix(Y_plot, Fs=Fs/H, Fs_F=N/Fs, title=title, figsize=figsize)
    if ylim is not None:
        plt.ylim(ylim)
    plt.tight_layout()
    plt.show()
    return Y

# Piirtää spectrogrammeja???
def plot_spectrogram(Y_h, Y_p, Fs=22050, N=4096, H=2048, figsize =(10, 2), ylim=None, clim=None, title_h='', title_p='', log=False):

    if log: 
        Y_h_plot = np.log(1 + 100 * Y_h)
        Y_p_plot = np.log(1 + 100 * Y_p)
    else: 
        Y_h_plot = Y_h
        Y_p_plot = Y_p
    plt.figure(figsize=figsize)
    ax = plt.subplot(1,2,1)
    libfmp.b.plot_matrix(Y_h_plot, Fs=Fs/H, Fs_F=N/Fs, ax=[ax], clim=clim,
                         title=title_h, figsize=figsize)
    if ylim is not None:
        ax.set_ylim(ylim)
        
    ax = plt.subplot(1,2,2)
    libfmp.b.plot_matrix(Y_p_plot, Fs=Fs/H, Fs_F=N/Fs, ax=[ax], clim=clim,
                         title=title_p, figsize=figsize)
    if ylim is not None:
        ax.set_ylim(ylim)
  
    plt.tight_layout()
    plt.show()


##################################################################
# Palautus signaali eli muokattu x
##################################################################
""" 
Tämän kohdan on tarkoitus palauttaa saatu signaali muokattuna.
Jotta pitch_service_... pystyy käyttämään sitä luokkaa
from HPS import process_signal
result = process_signal(x, sr) tyylisesti
"""

