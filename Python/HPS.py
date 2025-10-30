# %%
from ctypes import sizeof
import os, sys
import matplotlib
import numpy as np
from scipy import signal
import matplotlib.pyplot as plt
import IPython.display as ipd
import librosa.display
import soundfile as sf
import libfmp.b

# En tiedä mikä tätä vaivaa -> %matplotlib inline <- (tää pitäisi saada tohon alle ilman errorii)

##################################################################
# Tänne rakennetaan HPS signaalin käsittely menetelmä
# Jos tarvii inspistä niin step-by-step quide -> 
# https://www.audiolabs-erlangen.de/resources/MIR/FMP/C8/C8S1_HPS.html
##################################################################

# Äänen vastaanoton alustus (tajusin et tää saattaa olla ihan turha jos tulee __main__ 😂)
"""
Tähän voi tehdä signaalin alustus jutut eli määritellä vain seuraavat.
x (np.array): Input signal
filter_len (int): Filterin pituus
Fs (Int): Näytteen otto taajuus
N (Int): Frame pituus
H (Int): Hop pituudet
???
"""
x = np.array(1,2,3,4,5) # Tähän tulee se signaali
Fs = 22050
N = 1024
H = 512

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

# Filterin pituus muokataan sekkuneista freimeihin
def convert_s_to_frame(F_sec, Fs=Fs, N=N, H=H):
    """
    F_sec (float): Filterin pituus sekuntteina
    Fs (scalar): Näytteenottotaajuus
    N (int): Ikkunna koko
    H (int): Hop koko 
    """
    L_sec = int(np.ceil(F_sec * Fs / H))
    return L_sec

# Filterin pituus muokataan hertsit frekvenssi bineihin
def convert_herz_to_bins(F_Hz, Fs=Fs, N=N, H=H):
    """
    F_sec (float): Filterin pituus sekuntteina
    Fs (scalar): Näytteenottotaajuus
    N (int): Ikkunna koko
    H (int): Hop koko 
    """
    L_Hz = int(np.ceil(F_Hz * N / Fs))
    return L_Hz

# Tehdään kokonaisluvusta pariton
def odder(n):
    """
    n (int): Kokonaisluku???
    """
    if n % 2 == 0:
        n += 1
    return n

##################################################################
# HPS-analyysi (Harmonic-Percussive Separation)
##################################################################

def hps(x, Fs, N, L_sec, L_Hz, L_unit='physical', mask='binary', eps=0.001, detail=False):
    """
    x (np.ndarray): Sisääntulo signaali
    Fs (scalar): Näytteenottotaajuus x:n suhteen
    N (int): Ikkunan pituus
    H (int): Hop pituus
    L_h (float): Filtterin muookaus sekunneista frame
    L_p (float): Hertseistä filterin bineihin
    L_unit (str): Voi muokata 'physical' tai 'indices'
    mask (str): Voi muokata 'binary' tai 'soft'
    eps (float): Käytetään soft maskaamiseen (default = 0.001)
    detail (bool): Palauttaa detaalia tietoa

    Tarkoitus palauttaa:
    x_h (np.ndarray): Harmoninen signaali
    x_p (np.ndarray): Isku signaali (värähtely???)
    """
    
    assert L_unit in ['physical', 'indices']
    assert mask in ['binaary', 'soft']

    # stft
    X = librosa.stft(x, n_fft=N, hop_length=H, win_length=N, window='hann', center=True, pad_mode='constant')

    # Voima spectrum
    Y = np.abs(X) ** 2

    # Mediaani filteröinti
    if L_unit == 'physical':
        L_h = convert_s_to_frame(L_sec=L_h, Fs=Fs, N=N, H=H)
        L_p = convert_herz_to_bins(L_Hz=L_p, Fs=Fs, N=N, H=H)
    L_h = odder(L_h)
    L_p = odder(L_p)
    Y_h = median_filterH(Y, sizeof(L_h))
    Y_p = median_filterV(Y, sizeof(L_p))

    # Maskataan
    if mask == 'binary':
        M_h = np.int8(Y_h >= Y_p)
        M_p = np.int8(Y_h < Y_p)
    if mask == 'soft':
        eps = 0.00001
        M_h = (Y_h + eps / 2) / (Y_h + Y_p + eps)
        M_p = (Y_p + eps / 2) / (Y_h + Y_p + eps)
    X_h = X * M_h
    X_p = X * M_p

    # istf
    x_h = librosa.istft(X_h, hop_length=H, win_length=N, window='hann', center=True, length=x.size)
    x_p = librosa.istft(X_p, hop_length=H, win_length=N, window='hann', center=True, length=x.size)

    if detail:
        return x_h, x_p, dict(Y_h=Y_h, Y_p=Y_p, M_h=M_h, M_p=M_p, X_h=X_h, X_p=X_p)
    else:
        return x_h, x_p




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
# Tähän siis hps(...) niin pitäisi palauttaa tähän kohtaan tuloksen.

