import sys
import os

def repeat_to_size(data, size):
    """Repeat `data` to reach the desired `size`."""
    repeated = (data * ((size + len(data) - 1) // len(data)))[:size]
    return repeated

def write_coe(filename, data):
    """Write binary data to a .coe file."""
    with open(filename, 'w') as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        hex_values = [f"{byte:02X}" for byte in data]
        for i, val in enumerate(hex_values):
            if i < len(hex_values) - 1:
                f.write(val + ",\n")
            else:
                f.write(val + ";\n")

def extract_nes_rom(nes_path):
    with open(nes_path, 'rb') as f:
        header = f.read(16)
        if header[:4] != b"NES\x1a":
            raise ValueError("Not a valid .nes file")
        
        prg_rom_size = header[4] * 16 * 1024  # in bytes
        chr_rom_size = header[5] * 8 * 1024   # in bytes

        trainer_present = header[6] & 0x04
        if trainer_present:
            f.read(512)  # Skip trainer

        prg_rom = f.read(prg_rom_size)
        chr_rom = f.read(chr_rom_size) if chr_rom_size > 0 else b''

        return prg_rom, chr_rom

def main(nes_path):
    prg_rom, chr_rom = extract_nes_rom(nes_path)

    prg_rom_final = repeat_to_size(prg_rom, 32 * 1024)  # 32KB
    chr_rom_final = repeat_to_size(chr_rom, 8 * 1024)   # 8KB

    base = os.path.splitext(os.path.basename(nes_path))[0]
    write_coe(f"{base}_prg.coe", prg_rom_final)
    write_coe(f"{base}_chr.coe", chr_rom_final)

    print(f"Generated {base}_prg.coe (32KB) and {base}_chr.coe (8KB)")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python nes_extraction.py <file.nes>")
        sys.exit(1)
    main(sys.argv[1])
