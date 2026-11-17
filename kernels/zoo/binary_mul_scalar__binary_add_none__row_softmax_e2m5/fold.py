def fold(module, **params):
    return {"operand0": module.s0_operand.reshape(1) / 256, "operand1": module.s1_operand.reshape(-1) / 256}
