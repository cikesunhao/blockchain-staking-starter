package dev.starter.indexer;

import jakarta.annotation.PostConstruct;
import java.math.BigInteger;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.web3j.abi.EventEncoder;
import org.web3j.abi.FunctionReturnDecoder;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Event;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.DefaultBlockParameterName;
import org.web3j.protocol.core.methods.request.EthFilter;
import org.web3j.protocol.http.HttpService;

/**
 * Minimal event indexer skeleton.
 *
 * <p>It subscribes to Staked / Withdrawn / RewardPaid / EarlyExit logs for
 * one LockedStaking contract and prints them. The next step for a real
 * project is to replace
 * the log lines with persistence (JPA + Postgres) and to handle chain
 * reorganisations: do not treat a log as final until N confirmations,
 * and re-scan on restart from the last indexed block instead of LATEST.
 */
@Component
public class StakingEventListener {

    private static final Logger log = LoggerFactory.getLogger(StakingEventListener.class);

    private final Event stakedEvent = new Event(
            "Staked",
            List.of(new TypeReference<Address>(true) {}, new TypeReference<Uint256>() {}));
    private final Event withdrawnEvent = new Event(
            "Withdrawn",
            List.of(new TypeReference<Address>(true) {}, new TypeReference<Uint256>() {}));
    private final Event rewardPaidEvent = new Event(
            "RewardPaid",
            List.of(new TypeReference<Address>(true) {}, new TypeReference<Uint256>() {}));
    private final Event earlyExitEvent = new Event(
            "EarlyExit",
            List.of(
                    new TypeReference<Address>(true) {},
                    new TypeReference<Uint256>() {},
                    new TypeReference<Uint256>() {},
                    new TypeReference<Uint256>() {}));

    @Value("${indexer.rpc-url}")
    private String rpcUrl;

    @Value("${indexer.staking-address}")
    private String stakingAddress;

    @PostConstruct
    public void subscribe() {
        Web3j web3j = Web3j.build(new HttpService(rpcUrl));
        EthFilter filter = new EthFilter(
                DefaultBlockParameterName.LATEST,
                DefaultBlockParameterName.LATEST,
                stakingAddress);
        filter.addSingleTopic(EventEncoder.encode(stakedEvent));
        filter.addSingleTopic(EventEncoder.encode(withdrawnEvent));
        filter.addSingleTopic(EventEncoder.encode(rewardPaidEvent));
        filter.addSingleTopic(EventEncoder.encode(earlyExitEvent));

        web3j.ethLogFlowable(filter).subscribe(ethLog -> {
            String topic0 = ethLog.getTopics().get(0);
            String user = "0x" + ethLog.getTopics().get(1).substring(26);
            boolean isEarlyExit = topic0.equals(EventEncoder.encode(earlyExitEvent));
            List<org.web3j.abi.datatypes.Type> values = FunctionReturnDecoder.decode(
                    ethLog.getData(),
                    isEarlyExit
                            ? List.of(
                                    new TypeReference<Uint256>() {},
                                    new TypeReference<Uint256>() {},
                                    new TypeReference<Uint256>() {})
                            : List.of(new TypeReference<Uint256>() {}));
            BigInteger amount = (BigInteger) values.get(0).getValue();
            String name = topic0.equals(EventEncoder.encode(stakedEvent)) ? "Staked"
                    : topic0.equals(EventEncoder.encode(withdrawnEvent)) ? "Withdrawn"
                    : isEarlyExit ? "EarlyExit" : "RewardPaid";
            // TODO: persist (user, amount, txHash, blockNumber) instead of logging.
            if (isEarlyExit) {
                BigInteger penalty = (BigInteger) values.get(1).getValue();
                BigInteger forfeited = (BigInteger) values.get(2).getValue();
                log.info("{} user={} amount={} penalty={} forfeitedReward={} tx={} block={}",
                        name, user, amount, penalty, forfeited,
                        ethLog.getTransactionHash(), ethLog.getBlockNumber());
            } else {
                log.info("{} user={} amount={} tx={} block={}",
                        name, user, amount, ethLog.getTransactionHash(), ethLog.getBlockNumber());
            }
        }, error -> log.error("event subscription failed", error));
    }
}
