import { useCallback, useState } from "react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { getAptosClient } from "@/utils/aptosClient";
import { queryPlayPetsCollection } from "@/graphql/queryPlayPetsCollection";
import { padAddressIfNeeded } from "@/utils/address";
import { ABI } from "@/utils/abi";

const aptosClient = getAptosClient();

type Collection = {
  collection_id: string;
  collection_name: string;
  creator_address: string;
  uri: string;
  current_supply: any;
};

type CollectionHolder = {
  owner_address: string;
};

type CollectionResponse = {
  current_collections_v2: Collection[];
  current_collection_ownership_v2_view: CollectionHolder[];
};

export function useGetPlayPetsCollection() {
  const { account } = useWallet();
  const [collection, setCollection] = useState<Collection>();
  const [firstFewPlayPetsName, setFirstFewPlayPetsName] =
    useState<string[]>();
  const [loading, setLoading] = useState(false);

  const fetchCollection = useCallback(async () => {
    if (!account?.address) return;

    try {
      setLoading(true);

      const PlayPetsCollectionAddressResponse = (await aptosClient.view({
        payload: {
          function: `${ABI.address}::main::get_playpets_collection_address`,
        },
      })) as [`0x${string}`];

      const collectionAddress = padAddressIfNeeded(
        PlayPetsCollectionAddressResponse[0]
      );

      const collectionResponse: CollectionResponse =
        await aptosClient.queryIndexer({
          query: {
            query: queryPlayPetsCollection,
            variables: {
              collection_id: collectionAddress,
            },
          },
        });

      const firstFewPlayPets = await Promise.all(
        collectionResponse.current_collection_ownership_v2_view
          .filter((holder) => holder.owner_address !== account.address)
          // TODO: change to limit 3 in gql after indexer fix limit
          .slice(0, 3)
          .map((holder) =>
            aptosClient.view({
              payload: {
                function: `${ABI.address}::main::get_playpets`,
                functionArguments: [holder.owner_address],
              },
            })
          )
      );

      setCollection(collectionResponse.current_collections_v2[0]);
      setFirstFewPlayPetsName(firstFewPlayPets.map((x) => x[0] as string));
    } catch (error) {
      console.error("Error fetching PlayPets collection:", error);
    } finally {
      setLoading(false);
    }
  }, [account?.address]);

  return { collection, firstFewPlayPetsName, loading, fetchCollection };
}
