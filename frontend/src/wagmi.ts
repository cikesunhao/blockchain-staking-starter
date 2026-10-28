import { http, createConfig } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'

// 只用浏览器钱包（MetaMask 等），不用 WalletConnect，避免还要申请 projectId。
export const config = createConfig({
  chains: [sepolia],
  transports: {
    [sepolia.id]: http(import.meta.env.VITE_RPC_URL),
  },
  connectors: [injected()],
})
