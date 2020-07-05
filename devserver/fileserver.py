#!/bin/env python3

import serial
import os
import pathlib
import datetime

############### CHANGE HERE TO YOUR UART DEV
port = "/dev/tty.usbserial-0001"
fspath = os.path.abspath("filesystem")

uart = serial.Serial(port=port, baudrate=115200, rtscts=True, exclusive=True)

def log(str):
    print(datetime.datetime.now(), str)

def send_byte(b):
    while uart.cts == False:
        pass
    uart.write(b)

def read_byte():
    return uart.read(1)

def send_plain_file(filename: str):
    log("Sending plain file: \"" + filename + "\"")
    if os.path.exists(filename) and os.path.isfile(filename):
        log("Sending size")
        size = os.path.getsize(filename)
        sizel = (size % 256).to_bytes(1, 'big')
        sizeh = (size // 256).to_bytes(1, 'big')

        send_byte(sizel)
        send_byte(sizeh)

        with open(filename, "rb", buffering = 0) as file:
            log("file opened")
            while True:
                byte = file.read(1)
                if (byte == b''): 
                    break

                send_byte(byte)
            log("Send complete")
    else:
        if os.path.exists(filename) == False:
            log("File is absent")
        if os.path.isfile(filename) == False:
            log("Required object isn't file")

        send_byte(b'\0')
        send_byte(b'\0')

def recv_plain_file(filename):
    log('Will create file ' + filename)
    size = int.from_bytes(uart.read(2), "little")
    try:
        with open(filename, "wb") as file:
            file.write(uart.read(size))
        log("File written successfuly")
    except:
        log("File storing issue")

def get_catalog():
    flist = [p for p in pathlib.Path(fspath).iterdir() if p.is_file()]
    

def extract_file_name():
    name = uart.read_until(b'\0').decode('ascii', errors = 'ignore').replace('\0', '')
    return os.path.join(fspath, name)

log("Started")

while True:
    cmd = uart.read(1)
    if cmd == b'C':
        log('Get catalog required')
    elif cmd == b'p':
        log('Send plain file commad received')
        send_plain_file(extract_file_name())
        continue
    elif cmd == b'P': 
        log('Receive plain file command received')
        recv_plain_file(extract_file_name())
        continue


uart.close()
log("Uart closed")