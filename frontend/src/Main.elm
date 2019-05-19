module Main exposing (Model, Msg(..), Page(..), init, main, update, view)

import Browser
import Browser.Navigation exposing (Key)
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Json.Decode as D
import RemoteData exposing (RemoteData(..))
import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), Parser, oneOf, s)



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { view = view
        , init = init
        , onUrlChange = OnUrlChange
        , onUrlRequest = OnUrlRequest
        , update = update
        , subscriptions = always Sub.none
        }



-- MODEL


type alias Topic =
    { name : String
    , partitionCount : Int
    }


type alias Model =
    { apiUrl : String
    , page : Page
    , key : Key
    }


type alias Flags =
    { apiUrl : String }


type Page
    = TopicOverview (RemoteData Http.Error (List Topic))
    | TopicDetail Topic
    | PageNone


type Route
    = TopicsRoute
    | ViewTopicRoute String
    | NotFound


parseUrl : Url -> Route
parseUrl url =
    case Parser.parse routeParser url of
        Just route ->
            route

        Nothing ->
            NotFound


fetchTopics : String -> Cmd Msg
fetchTopics apiUrl =
    Http.get
        { url = apiUrl ++ "/api/topics"
        , expect = Http.expectJson (RemoteData.fromResult >> TopicsResponse) decodeTopics
        }


decodeTopic : D.Decoder Topic
decodeTopic =
    D.map2 Topic
        (D.field "name" D.string)
        (D.field "partition_count" D.int)


decodeTopics : D.Decoder (List Topic)
decodeTopics =
    D.list decodeTopic


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ Parser.map ViewTopicRoute (s "topic" </> Parser.string)
        , Parser.map TopicsRoute (s "topics")
        ]


getPath : Route -> String
getPath route =
    case route of
        NotFound ->
            "/404"

        TopicsRoute ->
            "/topics"

        ViewTopicRoute name ->
            "/topic/" ++ name


getPage : String -> Route -> ( Page, Cmd Msg )
getPage apiUrl route =
    case route of
        NotFound ->
            ( PageNone, Cmd.none )

        TopicsRoute ->
            ( TopicOverview Loading, fetchTopics apiUrl )

        ViewTopicRoute name ->
            ( TopicDetail { name = name, partitionCount = 1 }, Cmd.none )


init : Flags -> Url -> Key -> ( Model, Cmd Msg )
init flags url key =
    let
        ( page, cmd ) =
            parseUrl url |> getPage flags.apiUrl
    in
    ( { apiUrl = flags.apiUrl, page = page, key = key }, cmd )


type Msg
    = OnUrlRequest Browser.UrlRequest
    | OnUrlChange Url
    | TopicsResponse (RemoteData Http.Error (List Topic))
    | Noop


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnUrlChange url ->
            let
                ( newPage, cmd ) =
                    parseUrl url |> getPage model.apiUrl
            in
            ( { model | page = newPage }, cmd )

        Noop ->
            ( model, Cmd.none )

        OnUrlRequest urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Browser.Navigation.pushUrl model.key (Url.toString url)
                    )

                Browser.External url ->
                    ( model
                    , Browser.Navigation.load url
                    )

        TopicsResponse response ->
            let
                newPage =
                    case model.page of
                        TopicOverview _ ->
                            TopicOverview response

                        _ ->
                            model.page
            in
            ( { model | page = newPage }
            , Cmd.none
            )



---- VIEW ----


view : Model -> Browser.Document Msg
view model =
    { title = "Kafka UI"
    , body =
        case model.page of
            TopicDetail topic ->
                [ div [] [ text "Topic detail placeholder" ] ]

            TopicOverview topics ->
                [ viewTopics topics ]

            PageNone ->
                [ div [] [ text "Can not find page" ] ]
    }


viewTopicListItem : Topic -> Html Msg
viewTopicListItem topic =
    div []
        [ text topic.name, text ("(" ++ String.fromInt topic.partitionCount ++ " partitions)") ]


viewTopics : RemoteData Http.Error (List Topic) -> Html Msg
viewTopics topicsResponse =
    case topicsResponse of
        NotAsked ->
            div [] [ text "Should not be here!" ]

        Success topics ->
            div []
                (List.map viewTopicListItem topics)

        Failure error ->
            div [] [ text "Something went wrong while fetching topics" ]

        Loading ->
            div [] [ text "Loading topics, please hold on..." ]
