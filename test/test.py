# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 5)

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 2)


async def load_data_byte(dut, addr, data):
    await FallingEdge(dut.clk)
    dut.ui_in.value = data & 0xFF
    dut.uio_in.value = (1 << 3) | (addr & 0x7)

    await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.uio_in.value = 0
    dut.ui_in.value = 0


async def load_key_byte(dut, addr, data):
    await FallingEdge(dut.clk)
    dut.ui_in.value = data & 0xFF
    dut.uio_in.value = (1 << 4) | (addr & 0x3)

    await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.uio_in.value = 0
    dut.ui_in.value = 0


async def load_data64(dut, value):
    for i in range(8):
        await load_data_byte(dut, i, (value >> (8 * i)) & 0xFF)


async def load_key32(dut, value):
    for i in range(4):
        await load_key_byte(dut, i, (value >> (8 * i)) & 0xFF)


async def start_cipher(dut, decrypt_mode):
    await FallingEdge(dut.clk)
    dut.uio_in.value = (1 << 5) | ((decrypt_mode & 1) << 6)

    await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.uio_in.value = 0


async def wait_done(dut, timeout_cycles=200):
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        status = int(dut.uo_out.value)
        done = (status >> 1) & 1
        if done:
            return

    raise AssertionError("Timeout waiting for done")


async def read_data64(dut):
    result = 0

    for i in range(8):
        await FallingEdge(dut.clk)
        dut.uio_in.value = (1 << 7) | (i & 0x7)

        await FallingEdge(dut.clk)
        byte_val = int(dut.uo_out.value) & 0xFF
        result |= byte_val << (8 * i)

    await FallingEdge(dut.clk)
    dut.uio_in.value = 0

    return result


async def run_one_test(dut, plaintext, key):
    await load_data64(dut, plaintext)
    await load_key32(dut, key)

    await start_cipher(dut, 0)
    await wait_done(dut)
    ciphertext = await read_data64(dut)

    assert ciphertext != plaintext, (
        f"Ciphertext equals plaintext. plaintext={plaintext:016x}, key={key:08x}"
    )

    await load_data64(dut, ciphertext)

    await start_cipher(dut, 1)
    await wait_done(dut)
    decrypted = await read_data64(dut)

    dut._log.info(
        f"PT={plaintext:016x} KEY={key:08x} CT={ciphertext:016x} DEC={decrypted:016x}"
    )

    assert decrypted == plaintext, (
        f"Decrypt failed. expected={plaintext:016x}, got={decrypted:016x}"
    )


@cocotb.test()
async def test_crypto_core(dut):
    dut._log.info("Start crypto core test")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    vectors = [
        (0x0123456789ABCDEF, 0xA5A51234),
        (0x0000000000000000, 0x00000000),
        (0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF),
        (0x0000000000000001, 0x00000001),
        (0x8000000000000000, 0x80000000),
        (0xDEADBEEFCAFEBABE, 0x13579BDF),
        (0x1122334455667788, 0x2468ACE0),
        (0xA5A5A5A55A5A5A5A, 0x0F0FF0F0),
        (0x3C4D5E6F708192A3, 0x1A2B3C4D),
        (0xF0E1D2C3B4A59687, 0x89ABCDEF),
        (0x1234ABCD5678EF90, 0xCAFEBABE),
        (0x0BADF00D55AA33CC, 0xFACEFEED),
    ]

    for plaintext, key in vectors:
        await run_one_test(dut, plaintext, key)

    dut._log.info("All crypto tests passed")