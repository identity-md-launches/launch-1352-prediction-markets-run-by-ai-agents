// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "../src/VerdictToken.sol";
import {DeployVerdictToken} from "../script/DeployVerdictToken.s.sol";

/// @notice Stands in for the project factory: deploys the token through CREATE2, holds the supply and
///         pays it out the way the launch does. Only the test may drive it.
contract FactoryStandIn {
    address private immutable controller = msg.sender;

    modifier onlyController() {
        require(msg.sender == controller, "not the test");
        _;
    }

    function deploy(bytes memory code, bytes32 salt) external onlyController returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }

    function move(VerdictToken token, address to, uint256 amount) external onlyController returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @notice The launch flows the token has to carry exactly. A custom token launch mints the whole
///         supply to the factory; the factory forwards 10% to the MerkleDistributor, seeds the pool
///         with the requester's pool share and forwards the remainder. Every one of those transfers
///         must arrive whole, and the supply must not change along the way.
contract LaunchFlowTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 constant SWARM_BPS = 1_000;
    uint256 constant POOL_BPS = 8_000;
    uint64 constant LAUNCH_NUMBER = 7;

    address constant DISTRIBUTOR = address(0xD157);
    address constant CLAIMANT = address(0xC1A1);
    address constant POOL_MANAGER = address(0x9001);
    address constant REMAINDER_TO = address(0xd6302976E590b9b947DA8774b7f1246164e0ce98);

    FactoryStandIn factory;
    VerdictToken token;

    function setUp() public {
        factory = new FactoryStandIn();
        address at = factory.deploy(type(VerdictToken).creationCode, bytes32(uint256(LAUNCH_NUMBER)));
        token = VerdictToken(at);
    }

    function test_create2DeploymentMintsWholeSupplyToTheFactory() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_create2AddressIsPredictable() public view {
        bytes32 codeHash = keccak256(type(VerdictToken).creationCode);
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), bytes32(uint256(LAUNCH_NUMBER)), codeHash)
                    )
                )
            )
        );
        assertEq(address(token), predicted);
    }

    function test_swarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        assertTrue(factory.move(token, DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "the swarm's share arrived short");

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm));
        assertEq(token.balanceOf(CLAIMANT), swarm, "a claim arrived short");
        assertEq(token.balanceOf(DISTRIBUTOR), 0, "the distributor kept something back");
        assertEq(token.totalSupply(), SUPPLY, "the launch flows changed the supply");
    }

    function test_fullPayoutSplitsExactlyAndSumsToSupply() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        factory.move(token, DISTRIBUTOR, swarm);
        factory.move(token, POOL_MANAGER, pool);
        factory.move(token, REMAINDER_TO, remainder);

        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
        assertEq(token.balanceOf(REMAINDER_TO), remainder);
        assertEq(token.balanceOf(address(factory)), 0, "the factory kept something back");
        assertEq(swarm + pool + remainder, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_poolManagerCanReceiveAndReturnTokensWhole() public {
        // A trader buys from the pool and sells back into it. With no fee or burn on transfer,
        // what leaves the pool manager and what returns to it are exactly the stated amounts.
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        factory.move(token, POOL_MANAGER, pool);

        address trader = makeAddr("trader");
        uint256 bought = 12_345e18;
        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought, "a buy arrived short");

        vm.prank(trader);
        assertTrue(token.transfer(POOL_MANAGER, bought));
        assertEq(token.balanceOf(trader), 0, "a sell left dust behind");
        assertEq(token.balanceOf(POOL_MANAGER), pool, "a sell arrived short");
    }

    function test_poolManagerPullsThroughAllowanceWhole() public {
        // Uniswap v4 settles via transfer, but routers and periphery pull through transferFrom.
        address trader = makeAddr("trader");
        factory.move(token, trader, 1_000e18);
        vm.prank(trader);
        token.approve(POOL_MANAGER, 1_000e18);
        vm.prank(POOL_MANAGER);
        assertTrue(token.transferFrom(trader, POOL_MANAGER, 1_000e18));
        assertEq(token.balanceOf(POOL_MANAGER), 1_000e18);
        assertEq(token.allowance(trader, POOL_MANAGER), 0);
    }

    function test_RevertWhen_factoryMovesMoreThanTheSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, address(factory), SUPPLY, SUPPLY + 1)
        );
        factory.move(token, DISTRIBUTOR, SUPPLY + 1);
    }

    function test_deployScriptMintsToItsCaller() public {
        DeployVerdictToken script = new DeployVerdictToken();
        VerdictToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY, "the script's caller did not receive the supply");
        assertEq(deployed.name(), "Prediction Markets Run by AI Agents");
        assertEq(deployed.symbol(), "VERDICT");
        assertEq(deployed.decimals(), 18);
    }
}
