.text
.align 2
.globl _saveGPR
.globl saveGPR
_saveGPR:
saveGPR:
    std r14,-144(r1); std r15,-136(r1); std r16,-128(r1); std r17,-120(r1)
    std r18,-112(r1); std r19,-104(r1); std r20,-96(r1); std r21,-88(r1)
    std r22,-80(r1); std r23,-72(r1); std r24,-64(r1); std r25,-56(r1)
    std r26,-48(r1); std r27,-40(r1); std r28,-32(r1); std r29,-24(r1)
    std r30,-16(r1); std r31,-8(r1); blr
.globl _restGPR
.globl restGPR
_restGPR:
restGPR:
    ld r14,-144(r1); ld r15,-136(r1); ld r16,-128(r1); ld r17,-120(r1)
    ld r18,-112(r1); ld r19,-104(r1); ld r20,-96(r1); ld r21,-88(r1)
    ld r22,-80(r1); ld r23,-72(r1); ld r24,-64(r1); ld r25,-56(r1)
    ld r26,-48(r1); ld r27,-40(r1); ld r28,-32(r1); ld r29,-24(r1)
    ld r30,-16(r1); ld r31,-8(r1); blr
.globl _restGPRx
.globl restGPRx
_restGPRx:
restGPRx:
    ld r14,-144(r1); ld r15,-136(r1); ld r16,-128(r1); ld r17,-120(r1)
    ld r18,-112(r1); ld r19,-104(r1); ld r20,-96(r1); ld r21,-88(r1)
    ld r22,-80(r1); ld r23,-72(r1); ld r24,-64(r1); ld r25,-56(r1)
    ld r26,-48(r1); ld r27,-40(r1); ld r28,-32(r1); ld r29,-24(r1)
    ld r30,-16(r1); ld r31,-8(r1); ld r0,16(r1); mtlr r0; blr
