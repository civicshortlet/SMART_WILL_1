import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;
const wallet4 = accounts.get("wallet_4")!;

const contractName = "smart_will";

describe("Smart Will Contract Tests", () => {

  // Helper function to create a simple will
  const createSimpleWill = (
    owner: string,
    beneficiaries: string[],
    allocations: number[],
    releaseBlockHeight: number
  ) => {
    return simnet.callPublicFn(
      contractName,
      "create-will",
      [
        Cl.list(beneficiaries.map(b => Cl.principal(b))),
        Cl.list(allocations.map(a => Cl.uint(a))),
        Cl.uint(releaseBlockHeight)
      ],
      owner
    );
  };

  describe("Will Creation Tests", () => {
    it("should successfully create a will with valid parameters", () => {
      const releaseBlock = simnet.blockHeight + 100;
      const { result } = createSimpleWill(
        wallet1,
        [wallet2, wallet3],
        [1000000, 2000000],
        releaseBlock
      );

      expect(result).toBeOk(Cl.uint(1));

      // Verify will data was stored correctly
      const willInfo = simnet.callReadOnlyFn(
        contractName,
        "get-will-info",
        [Cl.uint(1)],
        wallet1
      );

      expect(willInfo.result).toBeSome(
        Cl.tuple({
          owner: Cl.principal(wallet1),
          "release-block-height": Cl.uint(releaseBlock),
          "total-allocation": Cl.uint(3000000),
          "total-claimed": Cl.uint(0),
          "beneficiary-count": Cl.uint(2),
          "is-cancelled": Cl.bool(false),
          "created-block": Cl.uint(simnet.blockHeight)
        })
      );
    });

    it("should fail to create will with release block in the past", () => {
      const { result } = createSimpleWill(
        wallet1,
        [wallet2],
        [1000000],
        simnet.blockHeight - 1
      );

      expect(result).toBeErr(Cl.uint(109)); // ERR_INVALID_RELEASE_BLOCK
    });

    it("should fail to create will with mismatched beneficiary and allocation counts", () => {
      const releaseBlock = simnet.blockHeight + 100;
      const { result } = simnet.callPublicFn(
        contractName,
        "create-will",
        [
          Cl.list([Cl.principal(wallet2), Cl.principal(wallet3)]),
          Cl.list([Cl.uint(1000000)]), // Only one allocation for two beneficiaries
          Cl.uint(releaseBlock)
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(104)); // ERR_INVALID_ALLOCATION
    });

    it("should fail to create will with zero allocation", () => {
      const releaseBlock = simnet.blockHeight + 100;
      const { result } = createSimpleWill(
        wallet1,
        [wallet2, wallet3],
        [1000000, 0],
        releaseBlock
      );

      expect(result).toBeErr(Cl.uint(104)); // ERR_INVALID_ALLOCATION (contract returns this for zero allocations in calculate-total-allocation)
    });

    it("should fail to create second will when owner already has one", () => {
      const releaseBlock = simnet.blockHeight + 100;

      // Create first will
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      // Try to create second will
      const { result } = createSimpleWill(
        wallet1,
        [wallet3],
        [500000],
        releaseBlock
      );

      expect(result).toBeErr(Cl.uint(102)); // ERR_WILL_ALREADY_EXISTS
    });

    it("should fail to create will with insufficient balance", () => {
      const releaseBlock = simnet.blockHeight + 100;
      const { result } = createSimpleWill(
        wallet1,
        [wallet2],
        [999999999999999], // Very large amount
        releaseBlock
      );

      expect(result).toBeErr(Cl.uint(108)); // ERR_INSUFFICIENT_BALANCE
    });

    it("should fail to create will with no beneficiaries", () => {
      const releaseBlock = simnet.blockHeight + 100;
      const { result } = simnet.callPublicFn(
        contractName,
        "create-will",
        [
          Cl.list([]),
          Cl.list([]),
          Cl.uint(releaseBlock)
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(103)); // ERR_INVALID_BENEFICIARY
    });
  });

  describe("Will Update Tests", () => {
    beforeEach(() => {
      // Create a will before each update test
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2, wallet3], [1000000, 2000000], releaseBlock);
    });

    it("should successfully update beneficiary allocation (increase)", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet2), Cl.uint(1500000)],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify the allocation was updated
      const beneficiaryInfo = simnet.callReadOnlyFn(
        contractName,
        "get-beneficiary-info",
        [Cl.uint(1), Cl.principal(wallet2)],
        wallet1
      );

      expect(beneficiaryInfo.result).toBeSome(
        Cl.tuple({
          allocation: Cl.uint(1500000),
          claimed: Cl.bool(false)
        })
      );
    });

    it("should successfully update beneficiary allocation (decrease)", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet2), Cl.uint(500000)],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify the allocation was decreased
      const beneficiaryInfo = simnet.callReadOnlyFn(
        contractName,
        "get-beneficiary-info",
        [Cl.uint(1), Cl.principal(wallet2)],
        wallet1
      );

      expect(beneficiaryInfo.result).toBeSome(
        Cl.tuple({
          allocation: Cl.uint(500000),
          claimed: Cl.bool(false)
        })
      );
    });

    it("should successfully add a new beneficiary", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet4), Cl.uint(500000)],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify the new beneficiary was added
      const beneficiaryInfo = simnet.callReadOnlyFn(
        contractName,
        "get-beneficiary-info",
        [Cl.uint(1), Cl.principal(wallet4)],
        wallet1
      );

      expect(beneficiaryInfo.result).toBeSome(
        Cl.tuple({
          allocation: Cl.uint(500000),
          claimed: Cl.bool(false)
        })
      );
    });

    it("should fail to update beneficiary when not the owner", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet2), Cl.uint(1500000)],
        wallet2 // Not the owner
      );

      expect(result).toBeErr(Cl.uint(101)); // ERR_WILL_NOT_FOUND
    });

    it("should fail to update beneficiary with zero allocation", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet2), Cl.uint(0)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(111)); // ERR_ZERO_ALLOCATION
    });

    it("should fail to update after release block height is reached", () => {
      // Mine blocks to reach release height
      simnet.mineEmptyBlocks(101);

      const { result } = simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet2), Cl.uint(1500000)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(105)); // ERR_RELEASE_CONDITION_NOT_MET
    });
  });

  describe("Will Cancellation Tests", () => {
    it("should successfully cancel a will and refund STX", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2, wallet3], [1000000, 2000000], releaseBlock);

      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-will",
        [],
        wallet1
      );

      expect(result).toBeOk(Cl.uint(3000000));

      // Verify will is marked as cancelled
      const willInfo = simnet.callReadOnlyFn(
        contractName,
        "get-will-info",
        [Cl.uint(1)],
        wallet1
      );

      expect(willInfo.result).toBeSome(
        Cl.tuple({
          owner: Cl.principal(wallet1),
          "release-block-height": Cl.uint(releaseBlock),
          "total-allocation": Cl.uint(3000000),
          "total-claimed": Cl.uint(0),
          "beneficiary-count": Cl.uint(2),
          "is-cancelled": Cl.bool(true),
          "created-block": Cl.uint(simnet.blockHeight - 1)
        })
      );
    });

    it("should fail to cancel will when not the owner", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-will",
        [],
        wallet2 // Not the owner
      );

      expect(result).toBeErr(Cl.uint(101)); // ERR_WILL_NOT_FOUND
    });

    it("should fail to cancel already cancelled will", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      // Cancel once
      simnet.callPublicFn(contractName, "cancel-will", [], wallet1);

      // Try to cancel again
      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-will",
        [],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(106)); // ERR_WILL_CANCELLED
    });

    it("should fail to cancel non-existent will", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-will",
        [],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(101)); // ERR_WILL_NOT_FOUND
    });
  });

  describe("Claim Tests", () => {
    it("should successfully claim allocation after release block", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2, wallet3], [1000000, 2000000], releaseBlock);

      // Mine blocks to reach release height
      simnet.mineEmptyBlocks(11);

      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        wallet2
      );

      expect(result).toBeOk(Cl.uint(1000000));

      // Verify beneficiary data is marked as claimed
      const beneficiaryInfo = simnet.callReadOnlyFn(
        contractName,
        "get-beneficiary-info",
        [Cl.uint(1), Cl.principal(wallet2)],
        wallet2
      );

      expect(beneficiaryInfo.result).toBeSome(
        Cl.tuple({
          allocation: Cl.uint(1000000),
          claimed: Cl.bool(true)
        })
      );
    });

    it("should fail to claim before release block height", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(105)); // ERR_RELEASE_CONDITION_NOT_MET
    });

    it("should fail to claim twice", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      // Mine blocks to reach release height
      simnet.mineEmptyBlocks(11);

      // First claim should succeed
      simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet2);

      // Second claim should fail
      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(107)); // ERR_ALREADY_CLAIMED
    });

    it("should fail to claim when not a beneficiary", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      // Mine blocks to reach release height
      simnet.mineEmptyBlocks(11);

      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        wallet4 // Not a beneficiary
      );

      expect(result).toBeErr(Cl.uint(103)); // ERR_INVALID_BENEFICIARY
    });

    it("should fail to claim from cancelled will", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      // Cancel the will
      simnet.callPublicFn(contractName, "cancel-will", [], wallet1);

      // Mine blocks to reach release height
      simnet.mineEmptyBlocks(11);

      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(106)); // ERR_WILL_CANCELLED
    });

    it("should fail to claim from non-existent will", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(999)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(101)); // ERR_WILL_NOT_FOUND
    });

    it("should allow multiple beneficiaries to claim independently", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2, wallet3], [1000000, 2000000], releaseBlock);

      // Mine blocks to reach release height
      simnet.mineEmptyBlocks(11);

      // Both beneficiaries should be able to claim
      const claim1 = simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet2);
      expect(claim1.result).toBeOk(Cl.uint(1000000));

      const claim2 = simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet3);
      expect(claim2.result).toBeOk(Cl.uint(2000000));
    });
  });

  describe("Read-Only Function Tests", () => {
    it("should return will info correctly", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-will-info",
        [Cl.uint(1)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          owner: Cl.principal(wallet1),
          "release-block-height": Cl.uint(releaseBlock),
          "total-allocation": Cl.uint(1000000),
          "total-claimed": Cl.uint(0),
          "beneficiary-count": Cl.uint(1),
          "is-cancelled": Cl.bool(false),
          "created-block": Cl.uint(simnet.blockHeight)
        })
      );
    });

    it("should return beneficiary info correctly", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-beneficiary-info",
        [Cl.uint(1), Cl.principal(wallet2)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          allocation: Cl.uint(1000000),
          claimed: Cl.bool(false)
        })
      );
    });

    it("should return owner will ID correctly", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-owner-will-id",
        [Cl.principal(wallet1)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "will-id": Cl.uint(1)
        })
      );
    });

    it("should correctly check if release condition is met", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      // Before release
      let result = simnet.callReadOnlyFn(
        contractName,
        "is-release-condition-met",
        [Cl.uint(1)],
        wallet1
      );
      expect(result.result).toBeBool(false);

      // After release
      simnet.mineEmptyBlocks(11);
      result = simnet.callReadOnlyFn(
        contractName,
        "is-release-condition-met",
        [Cl.uint(1)],
        wallet1
      );
      expect(result.result).toBeBool(true);
    });

    it("should correctly check if beneficiary can claim", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      // Before release - cannot claim
      let result = simnet.callReadOnlyFn(
        contractName,
        "can-claim",
        [Cl.uint(1), Cl.principal(wallet2)],
        wallet2
      );
      expect(result.result).toBeBool(false);

      // After release - can claim
      simnet.mineEmptyBlocks(11);
      result = simnet.callReadOnlyFn(
        contractName,
        "can-claim",
        [Cl.uint(1), Cl.principal(wallet2)],
        wallet2
      );
      expect(result.result).toBeBool(true);

      // After claiming - cannot claim again
      simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet2);
      result = simnet.callReadOnlyFn(
        contractName,
        "can-claim",
        [Cl.uint(1), Cl.principal(wallet2)],
        wallet2
      );
      expect(result.result).toBeBool(false);
    });

    it("should return will stats correctly", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2, wallet3], [1000000, 2000000], releaseBlock);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-will-stats",
        [Cl.uint(1)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "total-allocation": Cl.uint(3000000),
          "total-claimed": Cl.uint(0),
          "beneficiary-count": Cl.uint(2),
          "is-cancelled": Cl.bool(false)
        })
      );
    });

    it("should return will counter correctly", () => {
      const releaseBlock = simnet.blockHeight + 100;

      // Initially should be 0
      let result = simnet.callReadOnlyFn(
        contractName,
        "get-will-counter",
        [],
        wallet1
      );
      expect(result.result).toBeUint(0);

      // After creating a will, should be 1
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);
      result = simnet.callReadOnlyFn(
        contractName,
        "get-will-counter",
        [],
        wallet1
      );
      expect(result.result).toBeUint(1);
    });

    it("should return contract balance correctly", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-contract-balance",
        [],
        wallet1
      );

      expect(result).toBeUint(0);

      // After creating a will, balance should increase
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      const result2 = simnet.callReadOnlyFn(
        contractName,
        "get-contract-balance",
        [],
        wallet1
      );
      expect(result2.result).toBeUint(1000000);
    });
  });

  describe("Event Logging Tests", () => {
    it("should log will creation event", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-last-will-created-event",
        [],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "will-id": Cl.uint(1),
          owner: Cl.principal(wallet1),
          "total-allocation": Cl.uint(1000000),
          "release-block-height": Cl.uint(releaseBlock),
          "beneficiary-count": Cl.uint(1),
          "created-block": Cl.uint(simnet.blockHeight)
        })
      );
    });

    it("should log will update event", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet2), Cl.uint(1500000)],
        wallet1
      );

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-last-will-updated-event",
        [],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "will-id": Cl.uint(1),
          owner: Cl.principal(wallet1),
          beneficiary: Cl.principal(wallet2),
          "old-allocation": Cl.uint(1000000),
          "new-allocation": Cl.uint(1500000),
          "updated-block": Cl.uint(simnet.blockHeight)
        })
      );
    });

    it("should log will cancellation event", () => {
      const releaseBlock = simnet.blockHeight + 100;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      simnet.callPublicFn(contractName, "cancel-will", [], wallet1);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-last-will-cancelled-event",
        [],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "will-id": Cl.uint(1),
          owner: Cl.principal(wallet1),
          "refunded-amount": Cl.uint(1000000),
          "cancelled-block": Cl.uint(simnet.blockHeight)
        })
      );
    });

    it("should log claim event", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(wallet1, [wallet2], [1000000], releaseBlock);

      simnet.mineEmptyBlocks(11);
      simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet2);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-last-claim-event",
        [],
        wallet2
      );

      expect(result).toBeSome(
        Cl.tuple({
          "will-id": Cl.uint(1),
          beneficiary: Cl.principal(wallet2),
          "claimed-amount": Cl.uint(1000000),
          "claimed-block": Cl.uint(simnet.blockHeight)
        })
      );
    });
  });

  describe("Edge Cases and Complex Scenarios", () => {
    it("should handle maximum number of beneficiaries", () => {
      const releaseBlock = simnet.blockHeight + 100;
      const maxBeneficiaries = 50;
      const beneficiaries: string[] = [];
      const allocations: number[] = [];

      // Create 50 beneficiaries
      for (let i = 0; i < maxBeneficiaries; i++) {
        beneficiaries.push(wallet2);
        allocations.push(100000);
      }

      const { result } = createSimpleWill(
        wallet1,
        beneficiaries,
        allocations,
        releaseBlock
      );

      // Should succeed with max beneficiaries
      expect(result).toBeOk(Cl.uint(1));
    });

    it("should handle partial claims from multiple beneficiaries", () => {
      const releaseBlock = simnet.blockHeight + 10;
      createSimpleWill(
        wallet1,
        [wallet2, wallet3, wallet4],
        [1000000, 2000000, 3000000],
        releaseBlock
      );

      simnet.mineEmptyBlocks(11);

      // Only wallet2 claims
      simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet2);

      // Check will stats
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-will-stats",
        [Cl.uint(1)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "total-allocation": Cl.uint(6000000),
          "total-claimed": Cl.uint(1000000),
          "beneficiary-count": Cl.uint(3),
          "is-cancelled": Cl.bool(false)
        })
      );
    });

    it("should handle will lifecycle from creation to full claims", () => {
      const releaseBlock = simnet.blockHeight + 10;

      // Create will
      const createResult = createSimpleWill(
        wallet1,
        [wallet2, wallet3],
        [1000000, 2000000],
        releaseBlock
      );
      expect(createResult.result).toBeOk(Cl.uint(1));

      // Update beneficiary before release
      const updateResult = simnet.callPublicFn(
        contractName,
        "update-beneficiary",
        [Cl.principal(wallet2), Cl.uint(1500000)],
        wallet1
      );
      expect(updateResult.result).toBeOk(Cl.bool(true));

      // Mine blocks to reach release
      simnet.mineEmptyBlocks(11);

      // Both beneficiaries claim
      const claim1 = simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet2);
      expect(claim1.result).toBeOk(Cl.uint(1500000));

      const claim2 = simnet.callPublicFn(contractName, "claim", [Cl.uint(1)], wallet3);
      expect(claim2.result).toBeOk(Cl.uint(2000000));

      // Verify final state
      const willStats = simnet.callReadOnlyFn(
        contractName,
        "get-will-stats",
        [Cl.uint(1)],
        wallet1
      );

      expect(willStats.result).toBeSome(
        Cl.tuple({
          "total-allocation": Cl.uint(3500000),
          "total-claimed": Cl.uint(3500000),
          "beneficiary-count": Cl.uint(2),
          "is-cancelled": Cl.bool(false)
        })
      );
    });
  });
});
