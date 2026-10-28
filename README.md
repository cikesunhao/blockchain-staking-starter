# 区块链开发练手项目：质押（Staking）骨架

给资深 Java + 前端开发者的快速入门项目：一条主线走完「合约 → 前端 → 链下索引」。

**只用于 Sepolia 测试网学习。合约未经审计，不要部署到主网、不要放真实资金。**

本地验证状态：合约 `forge test` 3 个测试全部通过；前端 `npm run build` 已通过。Java 索引器因本机环境没有 JDK 未能本地编译，跑之前请在有 JDK 17 + Maven 的机器上先跑 `mvn spring-boot:run` 验证。

## 目录结构

```
contracts/   Foundry + OpenZeppelin 质押合约
  Staking.sol        原版双代币质押，含 3 个测试（对照用）
  LockedStaking.sol  锁仓版（当前主线），单一代币，含 6 个测试
frontend/    React + Vite + wagmi/viem，现已指向 LockedStaking
indexer/     Spring Boot + web3j，订阅 Staked/Withdrawn/RewardPaid/EarlyExit 事件
```

## 锁仓版（当前主线，面试重点）

`LockedStaking.sol`，单一代币：质押什么币，就赚什么币。规则只有三条：

- **锁仓 30 天**：每次质押都会把锁仓刷新为当前时间 + 30 天；锁仓内正常提取会被拒绝，必须走提前退出。
- **提前退出**：没收全部待领奖励，再扣本金的 5% 罚金，到手本金的 95%。
- **罚金去向**：没收的奖励 + 本金罚金即时分给剩余质押者，做法是提高 `rewardPerTokenStored`：`redistributed * 1e18 / 剩余总质押量`，O(1)，不用遍历用户。如果提前退出后无人质押，金额暂存进 `undistributedPool`，下一期奖励注资时一并分发，而不是归项目方。

面试能讲的取舍（都在合约注释里写明了）：

- 为什么用 `block.timestamp` 做锁仓：以天计，矿工能操纵的十几秒可以忽略；秒级竞价就不行。
- 为什么每次质押刷新锁仓：简单、防刷奖励，但会连带锁住老资金；生产版可以改按仓位分锁。
- 为什么奖励计算是 O(1)：用 `rewardPerToken` 累计，而不是每次遍历用户。
- 精度：奖励按秒算，700 币 / 7 天整除不尽会留几百 wei 的 dust，测试里用近似断言并注明了这一点，别在面试里说“精确等于”。

部署锁仓版（用专门的测试网私钥，不要用主网私钥）：

```bash
cd contracts
export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
export PRIVATE_KEY=0x你的测试网私钥
TOKEN=0x... forge script script/DeployLocked.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

部署后：先给合约转入奖励代币，再调用 `notifyRewardAmount(奖励数量)` 开启奖励期（默认 7 天）；前端 `.env` 里填锁仓合约地址和同一种代币地址。

## 1. 合约（已在本机实测通过）

```bash
cd contracts
forge test   # 9 passed：原版 3 个 + 锁仓版 6 个
```

部署到 Sepolia（用专门的测试网私钥，不要用主网私钥）：

```bash
export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
export PRIVATE_KEY=0x你的测试网私钥
STAKING_TOKEN=0x... REWARDS_TOKEN=0x... \
  forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast
```

部署后记下 Staking 合约地址，然后：

1. 给合约转入奖励代币，并调用 `notifyRewardAmount(奖励数量)` 开启奖励期（默认 7 天）；
2. 用户先 approve 质押代币，再调用 `stake`。

奖励逻辑是 Synthetix 风格的按秒线性分配：按质押份额分奖励，不是固定年化。想改业务逻辑，先改 `Staking.sol` 里的奖励期和 `rewardRate`，再补测试。

## 2. 前端（已指向锁仓版）

```bash
cd frontend
cp .env.example .env
# 把 VITE_STAKING_ADDRESS（锁仓合约）、VITE_STAKING_TOKEN_ADDRESS（同一种代币）、VITE_RPC_URL 填好
npm install
npm run dev
```

只用浏览器钱包（MetaMask 等）连接，不需要 WalletConnect projectId。页面会显示锁仓状态和剩余天数，提前退出前会预览本金罚金和没收的奖励。流程是两笔交易：先 approve，再 stake，顺序不能反。交易失败、用户拒绝、revert 都会在页面上显示原因。

## 3. Java 索引器

```bash
cd indexer
export RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
export STAKING_ADDRESS=0x部署后的合约地址
mvn spring-boot:run
```

骨架目前是把事件（含新增的 EarlyExit：用户、金额、罚金、没收奖励）打日志。做成可用版本前必须补两件事：

- 用数据库（JPA + Postgres）存事件，而不是只打日志；
- 处理链重组：事件不要一到就当最终态，等 N 个确认再落库，重启时从上次索引的区块续扫，而不是每次都从 LATEST 开始。

## 下一步建议（按这个顺序做，证据链最完整）

1. 给合约加模糊测试和不变性测试，再跑一次主网分叉测试；
2. 把项目 README 换成真实数据：合约地址、测试覆盖率、Gas 报告、安全修复记录；
3. 参加一次审计竞赛或给知名协议提 PR，积累公开记录；
4. 再横向扩展：Solana（Rust + Anchor）或 Move（二选一，不要并行）。

## 安全清单（上测试网前先过一遍）

- 不要手写代币和权限逻辑，生产用 OpenZeppelin；
- 所有外部调用走 `SafeERC20`，关键函数加 `nonReentrant`；
- 奖励代币要先转入合约再 `notifyRewardAmount`，否则会 revert；
- 私钥、RPC Key 只放环境变量，绝不进 git。
