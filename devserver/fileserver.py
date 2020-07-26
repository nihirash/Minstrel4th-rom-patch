#!env python3

import serial
import os
import datetime

############### CHANGE HERE TO YOUR UART DEV
port = "/dev/tty.usbserial-0001"
fspath = os.path.abspath("filesystem")
tapfile = 0

uart = serial.Serial(port=port, baudrate=115200, rtscts=True)

def log(str):
    print(datetime.datetime.now(), str)

def send_byte(b: bytes):
   while uart.cts == False:
       pass
   uart.write(b)
   #log("Sending " + str(int.from_bytes(b, "big")))

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

def merge_name(name):
    return os.path.join(fspath, name)

def file_info(filename):
    file = merge_name(filename)
    if os.path.isfile(file):
        return " " + str(os.path.getsize(file))
    elif os.path.isdir(file):
        return " <DIR>"

def get_catalog():
    flist = [p for p in os.listdir(fspath)]
    
    files = '\r'.join(map(lambda x: x + file_info(x) ,flist))
    log("Sending catalog")
    for b in bytes(files, 'ascii', 'ignore'):
        send_byte(b.to_bytes(1, 'little'))
    send_byte((255).to_bytes(1, 'little'))
    log("Finished")

def extract_file_name():
    name = uart.read_until(b'\0').decode('ascii', errors = 'ignore').replace('\0', '')
    return merge_name(name)

def load_dict_tap():
    try:
        blocksize = tapfile.read(1)
        tapfile.read(1)
        if (blocksize != b'\x1a'):
            send_byte(b'\0')
            log('wrong tape file - ')
            log(blocksize)
            return
        send_byte(b'\1')

        block_type = tapfile.read(1)
        send_byte(block_type)

        name = tapfile.read(10)
        for i in range(10):
            send_byte(name[i:i+1])
        
        if (uart.read(1) == b'\0'): 
            log('Cancelled')
            return

        log('Confirmed')
        
        datalenl = tapfile.read(1)
        datalenh = tapfile.read(1)

        dataorgl = tapfile.read(1)
        dataorgh = tapfile.read(1)
        org = int.from_bytes(dataorgl, "big") + 256 * int.from_bytes(dataorgh, "big")
        log("Data org " + str(org))

        for i in range(5):
            l = tapfile.read(1)
            h = tapfile.read(1)
            send_byte(l)
            send_byte(h)
            var_val = int.from_bytes(l, "big") + 256 * int.from_bytes(h, "big")
            log("Var: " + str(var_val))

        send_byte(datalenl)
        send_byte(datalenh)

        send_byte(dataorgl)
        send_byte(dataorgh)

        blocklen = int.from_bytes(datalenl, "big") + 256 * int.from_bytes(datalenh, "big") 
        log("Sending " + str(blocklen) + " bytes block")
        tapfile.read(3) # we don't need this bytes

        for i in range(blocklen):
            send_byte(tapfile.read(1))
        tapfile.read(1)
    except:
        send_byte(b'\0')


def tap_in():
    global tapfile
    fname = merge_name(extract_file_name())
    log("Tap file "+fname)
    if os.path.isfile(fname):
        try:
            tapfile.close()
        except:
            pass

        tapfile = open(fname, "rb")
        log("Tap opened!")
        send_byte(b'\1')
    else:
        send_byte(b'\0')


log("Started")
while True:
    cmd = uart.read(1)
    if cmd == b'T':
        log('Tape in')
        tap_in()
    if cmd == b'D':
        log('Load block from TAP')
        load_dict_tap()
    if cmd == b'C':
        log('Get catalog required')
        get_catalog()
    elif cmd == b'p':
        log('Send plain file commad received')
        send_plain_file(extract_file_name())
        continue
    elif cmd == b'P': 
        log('Receive plain file command received')
        recv_plain_file(extract_file_name())
        continue



log("Uart closed")