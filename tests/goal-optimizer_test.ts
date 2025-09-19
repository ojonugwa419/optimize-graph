import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Goal Optimizer: Basic Goal Creation Test",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const goalTitle = "Master Blockchain Development";
        const goalDescription = "Comprehensive blockchain engineering skill development";

        const block = chain.mineBlock([
            Tx.contractCall(
                'goal-optimizer',
                'create-goal',
                [
                    types.ascii(goalTitle),
                    types.utf8(goalDescription),
                    types.some(types.uint(144000)),
                    types.uint(1),
                    types.none(),
                    types.uint(500)
                ],
                deployer.address
            )
        ]);

        // Assert successful goal creation
        block.receipts[0].result.expectOk();
    }
});

Clarinet.test({
    name: "Goal Optimizer: Milestone Addition Test",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        const createGoalBlock = chain.mineBlock([
            Tx.contractCall(
                'goal-optimizer',
                'create-goal',
                [
                    types.ascii("Blockchain Learning"),
                    types.utf8("Advanced blockchain skills"),
                    types.some(types.uint(144000)),
                    types.uint(1),
                    types.none(),
                    types.uint(500)
                ],
                deployer.address
            )
        ]);

        const addMilestoneBlock = chain.mineBlock([
            Tx.contractCall(
                'goal-optimizer',
                'add-milestone',
                [
                    types.uint(1),
                    types.ascii("Smart Contract Mastery"),
                    types.utf8("Complete advanced smart contract programming")
                ],
                deployer.address
            )
        ]);

        // Assert milestone addition
        addMilestoneBlock.receipts[0].result.expectOk();
    }
});