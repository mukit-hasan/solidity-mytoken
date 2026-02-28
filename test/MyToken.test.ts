import { expect } from "chai";
import hre from "hardhat";

describe("MyToken", function () {

    async function deployTokenFixture() {
        const { ethers } = await hre.network.connect();
        const [owner, user1, user2] = await ethers.getSigners();

        // Deploy the Fee library first
        const FeeLib = await ethers.getContractFactory("Fee");
        const feeLib = await FeeLib.deploy();
        await feeLib.waitForDeployment();

        // Link the library when deploying MyToken
        const Token = await ethers.getContractFactory("MyToken", {
            libraries: {
                Fee: await feeLib.getAddress()
            }
        });

        const token = await Token.deploy(
            ethers.parseEther("0.001"),
            30
        );

        await token.depositToken(500000);
        await token.depositEtr({ value: ethers.parseEther("10") });
        await token.updateState(1);

        return { token, owner, user1, user2, ethers };
    }

    describe("Deployment", function () {
        it("mints 1 million tokens to owner", async function () {
            const { token, owner, ethers } = await deployTokenFixture();
            
            // owner balance + contract balance should equal total supply
            const ownerBalance = await token.balanceOf(owner.address);
            const contractBalance = await token.balanceOf(await token.getAddress());
            
            expect(ownerBalance + contractBalance).to.equal(ethers.parseUnits("1000000", 18));
        });

        it("sets owner correctly", async function () {
            const { token, owner } = await deployTokenFixture();
            expect(await token.owner()).to.equal(owner.address);
        });
    });

    describe("buyToken", function () {
        it("gives tokens when buying with ETH", async function () {
            const { token, user1, ethers } = await deployTokenFixture();
            await token.connect(user1).buyToken(0, {
                value: ethers.parseEther("1")
            });
            expect(await token.balanceOf(user1.address)).to.be.gt(0);
        });

        it("fails below minBuy", async function () {
            const { token, user1, ethers } = await deployTokenFixture();
            await expect(
                token.connect(user1).buyToken(0, {
                    value: ethers.parseEther("0.0001")
                })
            ).to.be.revertedWith("below minimum buy");
        });

        it("fails when paused", async function () {
            const { token, user1, ethers } = await deployTokenFixture();
            await token.updateState(2);
            await expect(
                token.connect(user1).buyToken(0, {
                    value: ethers.parseEther("1")
                })
            ).to.be.revertedWith("Is not Active");
        });

        it("collects fees", async function () {
            const { token, user1, ethers } = await deployTokenFixture();
            await token.connect(user1).buyToken(0, {
                value: ethers.parseEther("1")
            });
            expect(await token.collectedFee()).to.be.gt(0);
        });
    });

    describe("sellToken", function () {
        it("gives ETH back when selling", async function () {
            const { token, user1, ethers } = await deployTokenFixture();
            await token.connect(user1).buyToken(0, {
                value: ethers.parseEther("1")
            });
            const ethBefore = await ethers.provider.getBalance(user1.address);
            await token.connect(user1).sellToken(10, 0);
            const ethAfter = await ethers.provider.getBalance(user1.address);
            expect(ethAfter).to.be.gt(ethBefore);
        });

        it("fails with not enough tokens", async function () {
            const { token, user2 } = await deployTokenFixture();
            await expect(
                token.connect(user2).sellToken(100, 0)
            ).to.be.revertedWith("not enough tokens");
        });
    });

    describe("withdrawEthFee", function () {
        it("lets owner withdraw fees after trades", async function () {
            const { token, user1, ethers } = await deployTokenFixture();
            await token.connect(user1).buyToken(0, {
                value: ethers.parseEther("1")
            });
            await token.withdrawEthFee();
            expect(await token.collectedFee()).to.equal(0);
        });

        it("fails when no fees collected", async function () {
            const { token } = await deployTokenFixture();
            await expect(token.withdrawEthFee())
                .to.be.revertedWith("No fee to collect");
        });
    });

    describe("transferOwnership", function () {
        it("transfers ownership correctly", async function () {
            const { token, user1 } = await deployTokenFixture();
            await token.transferOwnership(user1.address);
            expect(await token.owner()).to.equal(user1.address);
        });

        it("fails with zero address", async function () {
            const { token, ethers } = await deployTokenFixture();
            await expect(
                token.transferOwnership(ethers.ZeroAddress)
            ).to.be.revertedWith("zero address");
        });
    });
});