import { useState } from 'react'
import { formatEther, parseEther } from 'viem'
import { useAccount, useConnect, useDisconnect, useReadContract, useWriteContract } from 'wagmi'
import { erc20Abi, stakingAbi } from './abi'

// 注意：前端现在指向 LockedStaking 合约。VITE_STAKING_ADDRESS 是锁仓合约地址，
// VITE_STAKING_TOKEN_ADDRESS 是唯一的质押/奖励代币地址。
const stakingAddress = import.meta.env.VITE_STAKING_ADDRESS as `0x${string}`
const stakingTokenAddress = import.meta.env.VITE_STAKING_TOKEN_ADDRESS as `0x${string}`

function short(address: string) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

export default function App() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  const { writeContractAsync, isPending } = useWriteContract()
  const [amount, setAmount] = useState('')
  const [status, setStatus] = useState('')

  const readArgs = address ? ([address] as const) : undefined
  const { data: staked } = useReadContract({
    address: stakingAddress,
    abi: stakingAbi,
    functionName: 'balanceOf',
    args: readArgs,
    query: { enabled: !!address },
  })
  const { data: earned } = useReadContract({
    address: stakingAddress,
    abi: stakingAbi,
    functionName: 'earned',
    args: readArgs,
    query: { enabled: !!address },
  })
  const { data: lockEnd } = useReadContract({
    address: stakingAddress,
    abi: stakingAbi,
    functionName: 'lockEndOf',
    args: readArgs,
    query: { enabled: !!address },
  })
  const { data: locked } = useReadContract({
    address: stakingAddress,
    abi: stakingAbi,
    functionName: 'isLocked',
    args: readArgs,
    query: { enabled: !!address },
  })
  const { data: walletBalance } = useReadContract({
    address: stakingTokenAddress,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: readArgs,
    query: { enabled: !!address },
  })

  // 提前退出预览：本金罚金 5% + 没收全部待领奖励。链上以合约为准，
  // 这里只是让用户在点按钮前看到代价，避免“惊喜扣款”。
  const amountValue = amount ? parseEther(amount) : 0n
  const penaltyPreview = (amountValue * 5n) / 100n
  const lockEndDate = lockEnd ? new Date(Number(lockEnd) * 1000) : null
  const daysLeft =
    lockEnd && Number(lockEnd) * 1000 > Date.now()
      ? Math.ceil((Number(lockEnd) * 1000 - Date.now()) / 86_400_000)
      : 0

  async function run(label: string, fn: () => Promise<unknown>) {
    try {
      setStatus(`${label}交易已提交，等待确认……`)
      await fn()
      setStatus(`${label}成功`)
    } catch (e) {
      setStatus(`${label}失败：${e instanceof Error ? e.message.split('\n')[0] : '未知错误'}`)
    }
  }

  async function handleStake() {
    if (!amount) return
    const value = parseEther(amount)
    await run('质押', async () => {
      await writeContractAsync({
        address: stakingTokenAddress,
        abi: erc20Abi,
        functionName: 'approve',
        args: [stakingAddress, value],
      })
      await writeContractAsync({
        address: stakingAddress,
        abi: stakingAbi,
        functionName: 'stake',
        args: [value],
      })
    })
  }

  return (
    <main style={{ maxWidth: 640, margin: '40px auto', fontFamily: 'system-ui, sans-serif', padding: 16 }}>
      <h1>锁仓质押练手项目</h1>
      <p>Sepolia 测试网专用。质押后锁仓 30 天，提前退出扣本金 5% 并没收待领奖励，罚金分给剩余质押者。</p>

      {!isConnected ? (
        <button onClick={() => connect({ connector: connectors[0] })}>连接钱包</button>
      ) : (
        <>
          <p>
            已连接：{address && short(address)} <button onClick={() => disconnect()}>断开</button>
          </p>
          <p>钱包代币余额：{walletBalance ? formatEther(walletBalance) : '-'}</p>
          <p>已质押：{staked ? formatEther(staked) : '-'}</p>
          <p>可领奖励：{earned ? formatEther(earned) : '-'}</p>
          <p>
            锁仓状态：{locked ? `锁定中，约 ${daysLeft} 天后解锁` : '已解锁'}
            {lockEndDate && lockEndDate.getTime() > 0 && `（解锁时间：${lockEndDate.toLocaleString()}）`}
          </p>

          <input
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="输入数量，例如 10"
            style={{ padding: 8, marginRight: 8 }}
          />
          <button disabled={isPending} onClick={handleStake}>
            质押（会刷新 30 天锁仓）
          </button>{' '}
          <button
            disabled={isPending || !amount || !!locked}
            onClick={() =>
              run('正常提取', () =>
                writeContractAsync({
                  address: stakingAddress,
                  abi: stakingAbi,
                  functionName: 'withdraw',
                  args: [parseEther(amount)],
                }),
              )
            }
          >
            正常提取
          </button>{' '}
          <button
            disabled={isPending || !amount || !locked}
            onClick={() =>
              run('提前退出', () =>
                writeContractAsync({
                  address: stakingAddress,
                  abi: stakingAbi,
                  functionName: 'earlyExit',
                  args: [parseEther(amount)],
                }),
              )
            }
          >
            提前退出
          </button>{' '}
          <button
            disabled={isPending}
            onClick={() =>
              run('领奖', () =>
                writeContractAsync({
                  address: stakingAddress,
                  abi: stakingAbi,
                  functionName: 'getReward',
                  args: [],
                }),
              )
            }
          >
            领取奖励
          </button>
          {amount && locked && (
            <p>
              提前退出预览：本金罚金约 {formatEther(penaltyPreview)}，另没收全部待领奖励
              {earned ? `（约 ${formatEther(earned)}）` : ''}。到手约{' '}
              {formatEther(amountValue - penaltyPreview)}。
            </p>
          )}
          {status && <p>{status}</p>}
        </>
      )}
    </main>
  )
}
